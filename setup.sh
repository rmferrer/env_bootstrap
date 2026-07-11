#!/usr/bin/env bash
# Public bootstrap. Handles all interactive auth setup, then clones the
# private environment repo and hands off to its bootstrap.sh for chezmoi.
#
# macOS uses Homebrew. Linux uses distro package managers + official curl
# installers — works fine as root or non-root, no user-creation dance.
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
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

# Use sudo if not already root. On Linux running as root, SUDO is empty.
SUDO=""
[[ "${EUID:-$(id -u)}" -ne 0 ]] && SUDO="sudo"

apt_install() { $SUDO apt-get install -y --no-install-recommends "$@"; }

log "rmferrer/env_bootstrap setup.sh"
info "OS:           $OS"
info "Arch:         $ARCH"
info "User:         $USER  (UID $(id -u))"
info "Home:         $HOME"
info "Clone target: $TARGET"
info "Date:         $(date)"

# ── macOS: refuse running as root; Linux: any user is fine ────────────────────
if [[ "$OS" == "Darwin" && "${EUID:-$(id -u)}" -eq 0 ]]; then
  err "Refusing to run as root on macOS. Log in as your regular user account."
  exit 1
fi

case "$OS" in

  # ─── macOS ────────────────────────────────────────────────────────────────
  Darwin)
    log "[1/3] Homebrew"
    if command -v brew &>/dev/null; then
      skip "brew already installed at $(command -v brew)"
      info "Version: $(brew --version | head -1)"
    else
      info "Installing Homebrew (downloads + compiles, can take 5+ min)"
      NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      ok "Homebrew installed"
    fi
    load_brew_env
    info "brew path: $(command -v brew)"

    log "[2/3] 1Password desktop app"
    if [[ -d /Applications/1Password.app ]]; then
      if brew list --cask 1password &>/dev/null; then
        skip "1Password.app already installed (managed by Homebrew)"
      else
        info "1Password.app exists at /Applications but isn't tracked by Homebrew"
        existing_ver="$(defaults read /Applications/1Password.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo unknown)"
        cask_ver="$(brew info --cask 1password 2>/dev/null | awk 'NR==1 {print $3}')"
        cask_ver="${cask_ver:-unknown}"
        info "On-disk version: $existing_ver  |  Homebrew cask version: $cask_ver"
        info "Adopting (bookkeeping only — does not touch the on-disk binary)..."
        brew install --cask --adopt 1password
        if [[ "$existing_ver" != "$cask_ver" && "$existing_ver" != unknown && "$cask_ver" != unknown ]]; then
          info "Versions differ — 1Password's auto-updater keeps the app current regardless of brew."
        fi
        ok "1Password.app adopted by Homebrew"
      fi
    else
      info "Installing 1Password desktop app (cask, ~150MB)..."
      brew install --cask 1password
      ok "1Password.app installed"
    fi

    log "[3/3] 1Password CLI"
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

    info "Pointing SSH_AUTH_SOCK at 1Password's agent socket..."
    export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    if [[ -S "$SSH_AUTH_SOCK" ]]; then
      ok "SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
    else
      err "1Password SSH agent socket not found at $SSH_AUTH_SOCK"
      err "Confirm 'Use the SSH agent' is enabled in 1Password Settings → Developer."
      exit 1
    fi
    if ssh-add -l &>/dev/null; then
      ok "SSH agent has keys:"
      ssh-add -l | sed 's/^/        /'
    else
      err "SSH agent has no identities. Sign into a 1Password account that contains SSH keys."
      exit 1
    fi
    ;;

  # ─── Linux ────────────────────────────────────────────────────────────────
  Linux)
    if ! command -v apt-get &>/dev/null; then
      err "Only Debian/Ubuntu (apt-get) is currently supported on Linux."
      err "Add support for $(. /etc/os-release && echo "$ID") if you need it."
      exit 1
    fi

    log "[1/2] Distro packages (git, curl, ca-certificates)"
    info "Refreshing apt index..."
    $SUDO apt-get update -qq
    apt_install git curl ca-certificates
    ok "Distro packages installed"

    # No 1Password on Linux: chezmoi templates don't read any op:// secrets
    # (public signing keys are inlined in .chezmoidata.toml), and SSH auth +
    # commit signing both go through the agent forwarded from the laptop
    # (ssh -A). op CLI standalone sign-in also can't handle accounts with
    # Duo/security-key MFA, so requiring it here would block work devboxes.

    log "[2/2] SSH agent check"
    info "Checking SSH agent (should have keys forwarded from your laptop)..."
    if ssh-add -l &>/dev/null; then
      ok "SSH agent has keys:"
      ssh-add -l | sed 's/^/        /'
    else
      err "No SSH keys in agent. Reconnect with 'ssh -A' to forward your 1Password SSH agent."
      exit 1
    fi
    ;;

  *)
    err "Unsupported OS: $OS"
    exit 1
    ;;
esac

# ── Step 4: Clone private repo (and pull latest if it already exists) ────────
log "Clone or update private environment repo"
if [[ -d "$TARGET/.git" ]]; then
  info "Existing repo at $TARGET — pulling latest..."
  info "HEAD before: $(git -C "$TARGET" log -1 --oneline 2>&1)"
  git -C "$TARGET" pull --ff-only
  ok "HEAD after:  $(git -C "$TARGET" log -1 --oneline)"
elif [[ -d "$TARGET" ]]; then
  err "$TARGET exists but isn't a git repo. Remove it and re-run."
  exit 1
else
  info "Cloning $PRIVATE_REPO → $TARGET"
  mkdir -p "$(dirname "$TARGET")"
  git clone "$PRIVATE_REPO" "$TARGET"
  ok "Clone complete: $(git -C "$TARGET" log -1 --oneline)"
fi

log "Handoff to private bootstrap.sh"
info "Running: bash $TARGET/bootstrap.sh"
exec bash "$TARGET/bootstrap.sh"
