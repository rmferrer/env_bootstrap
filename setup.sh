#!/usr/bin/env bash
# Public bootstrap. Handles all interactive auth setup (1Password sign-in,
# SSH agent / CLI integration), then clones the private environment repo
# and hands off to its bootstrap.sh for chezmoi.
#
# Run via:
#   /bin/bash -c "$(curl -fsSL https://bit.ly/rmferrer_env_bootstrap)"
# or:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rmferrer/env_bootstrap/master/setup.sh)"

set -euo pipefail

PRIVATE_REPO="git@github.com:rmferrer/environment.git"
TARGET="$HOME/code/env"
OS="$(uname -s)"
ARCH="$(uname -m)"

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    [OK]   %s\n' "$*"; }
skip() { printf '    [skip] %s\n' "$*"; }
err()  { printf '\nERROR: %s\n' "$*" >&2; }

pause() {
  printf '\n==> %s\n    Press ENTER to continue.\n' "$1"
  read -r _ </dev/tty
}

load_brew_env() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    info "Loaded Homebrew env from /opt/homebrew"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
    info "Loaded Homebrew env from /usr/local"
  elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    info "Loaded Homebrew env from /home/linuxbrew/.linuxbrew"
  else
    info "No Homebrew found on disk yet"
  fi
}

log "rmferrer/env_bootstrap setup.sh"
info "OS:           $OS"
info "Arch:         $ARCH"
info "User:         $USER"
info "Home:         $HOME"
info "Clone target: $TARGET"
info "Date:         $(date)"

# ── Step 1: Homebrew ──────────────────────────────────────────────────────────
log "[1/4] Homebrew"
if command -v brew &>/dev/null; then
  skip "brew already installed at $(command -v brew)"
  info "Version: $(brew --version | head -1)"
else
  info "brew not found — installing (downloads + compiles, can take 5+ min)"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ok "Homebrew installed"
fi
load_brew_env
info "brew path: $(command -v brew)"

# ── Step 2 & 3: per-OS 1Password ──────────────────────────────────────────────
case "$OS" in
  Darwin)
    log "[2/4] 1Password desktop app"
    if [[ -d /Applications/1Password.app ]]; then
      if brew list --cask 1password &>/dev/null; then
        skip "1Password.app already installed (managed by Homebrew)"
      else
        info "1Password.app exists at /Applications but isn't tracked by Homebrew"
        info "Adopting existing install into Homebrew..."
        brew install --cask --adopt 1password
        ok "1Password.app adopted by Homebrew"
      fi
    else
      info "Installing 1Password desktop app (cask, ~150MB)..."
      brew install --cask 1password
      ok "1Password.app installed"
    fi

    log "[3/4] 1Password CLI"
    if command -v op &>/dev/null; then
      skip "op already installed at $(command -v op)"
      info "Version: $(op --version)"
    else
      info "Installing 1Password CLI (cask)..."
      brew install --cask 1password-cli
      ok "op installed: $(op --version)"
    fi

    info "Launching 1Password.app..."
    open -a 1Password || info "(could not open 1Password — open it manually)"
    pause "In 1Password: sign in to your account(s), then Settings → Developer → enable BOTH:
      • Use the SSH agent
      • Integrate with 1Password CLI"

    info "Verifying CLI integration via 'op account list'..."
    if op account list &>/dev/null; then
      ok "op CLI integration is working. Accounts:"
      op account list | sed 's/^/        /'
    else
      err "'op account list' failed. Is 'Integrate with 1Password CLI' enabled in 1Password Settings → Developer?"
      exit 1
    fi

    info "Checking SSH agent socket..."
    if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
      ok "SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
    else
      info "(SSH_AUTH_SOCK not set in this shell — that's fine; ~/.zshrc will set it after dotfiles apply)"
    fi
    ;;

  Linux)
    log "[2/4] 1Password CLI"
    if command -v op &>/dev/null; then
      skip "op already installed at $(command -v op)"
      info "Version: $(op --version)"
    else
      info "Installing 1Password CLI (Homebrew formula)..."
      brew install 1password-cli
      ok "op installed: $(op --version)"
    fi

    log "[3/4] 1Password sign-in"
    if op account list &>/dev/null; then
      skip "Already have 1Password accounts configured:"
      op account list | sed 's/^/        /'
    else
      info "No accounts yet — running 'op account add'"
      info "Have ready: sign-in URL, email, secret key, master password"
      op account add </dev/tty
    fi

    info "Running 'op signin' (will prompt for master password)..."
    eval "$(op signin </dev/tty)"
    ok "Signed in to 1Password CLI"

    info "Checking SSH agent (should have keys forwarded from your laptop)..."
    if ssh-add -l &>/dev/null; then
      ok "SSH agent has keys:"
      ssh-add -l | sed 's/^/        /'
    else
      err "No SSH keys in agent. Reconnect with 'ssh -A' to forward your 1Password SSH agent from your laptop."
      exit 1
    fi
    ;;

  *)
    err "Unsupported OS: $OS"
    exit 1
    ;;
esac

# ── Step 4: Clone private repo ────────────────────────────────────────────────
log "[4/4] Clone private environment repo"
if [[ -d "$TARGET" ]]; then
  skip "Target directory already exists: $TARGET"
  if [[ -d "$TARGET/.git" ]]; then
    info "Existing repo remote:"
    git -C "$TARGET" remote -v 2>&1 | sed 's/^/        /'
    info "Existing repo HEAD: $(git -C "$TARGET" log -1 --oneline 2>&1)"
  fi
else
  info "Cloning $PRIVATE_REPO"
  info "Destination: $TARGET"
  mkdir -p "$(dirname "$TARGET")"
  git clone "$PRIVATE_REPO" "$TARGET"
  ok "Clone complete: $(git -C "$TARGET" log -1 --oneline)"
fi

log "Handoff to private bootstrap.sh"
info "exec $TARGET/bootstrap.sh"
exec "$TARGET/bootstrap.sh"
