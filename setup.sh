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

# ── Preflight: handle running as root ─────────────────────────────────────────
# On Linux: bootstrap a non-root user and exit (the user has to reconnect with
#   `ssh -A` to get agent forwarding for the private repo clone).
# On macOS: just refuse — there's no legitimate reason to bootstrap as root.
bootstrap_linux_user() {
  local new_user="${INIT_USER:-rmferrer}"

  log "Running as root on Linux — bootstrapping a non-root user first"
  info "Target user:  $new_user  (override with INIT_USER=<name>)"
  info "Hostname:     $(hostname)"
  info "OS release:   $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"

  log "[user] Account"
  if id "$new_user" &>/dev/null; then
    skip "User '$new_user' already exists (UID $(id -u "$new_user"))"
  else
    useradd -m -s /bin/bash "$new_user"
    ok "Created $new_user (UID $(id -u "$new_user"))"
  fi

  log "[user] Sudo group"
  local sudo_group
  if getent group sudo &>/dev/null; then
    sudo_group=sudo
  elif getent group wheel &>/dev/null; then
    sudo_group=wheel
  else
    err "Neither 'sudo' nor 'wheel' group exists. Install sudo first."
    exit 1
  fi
  if id -nG "$new_user" | tr ' ' '\n' | grep -qx "$sudo_group"; then
    skip "$new_user is already in $sudo_group"
  else
    usermod -aG "$sudo_group" "$new_user"
    ok "Added $new_user to $sudo_group"
  fi

  log "[user] Passwordless sudo"
  local sudoers_file="/etc/sudoers.d/90-${new_user}"
  if [[ -f "$sudoers_file" ]]; then
    skip "$sudoers_file already exists"
  else
    echo "$new_user ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
    chmod 440 "$sudoers_file"
    ok "Wrote $sudoers_file"
  fi

  log "[user] SSH authorized_keys"
  local user_ssh="/home/$new_user/.ssh"
  local user_keys="$user_ssh/authorized_keys"
  if [[ -f "$user_keys" ]]; then
    skip "$user_keys already exists ($(wc -l <"$user_keys") line(s))"
  elif [[ -f /root/.ssh/authorized_keys ]]; then
    mkdir -p "$user_ssh"
    cp /root/.ssh/authorized_keys "$user_keys"
    chown -R "$new_user:$new_user" "$user_ssh"
    chmod 700 "$user_ssh"
    chmod 600 "$user_keys"
    ok "Copied $(wc -l <"$user_keys") key(s) from /root/.ssh; perms 700/600"
  else
    err "/root/.ssh/authorized_keys not found. Add your public key to"
    err "  $user_keys manually before disconnecting."
    exit 1
  fi

  log "User bootstrap complete!"
  info "Next steps (from your laptop):"
  info "  1. Disconnect from this root session."
  info "  2. Reconnect as $new_user WITH agent forwarding so your 1Password"
  info "     SSH agent on the laptop can authenticate the private repo clone:"
  info "       ssh -A $new_user@$(hostname)"
  info "  3. Re-run this script — the non-root flow continues from here:"
  info "       /bin/bash -c \"\$(curl -fsSL https://bit.ly/rmferrer_env_bootstrap)\""
  exit 0
}

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  case "$OS" in
    Linux)  bootstrap_linux_user ;;
    Darwin) err "Refusing to run as root on macOS. Log in as your regular account."; exit 1 ;;
    *)      err "Refusing to run as root on $OS."; exit 1 ;;
  esac
fi

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
        existing_ver="$(defaults read /Applications/1Password.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo unknown)"
        cask_ver="$(brew info --cask 1password 2>/dev/null | awk 'NR==1 {print $3}')"
        cask_ver="${cask_ver:-unknown}"
        info "On-disk version: $existing_ver  |  Homebrew cask version: $cask_ver"
        info "Adopting (bookkeeping only — does not touch the on-disk binary)..."
        brew install --cask --adopt 1password
        if [[ "$existing_ver" != "$cask_ver" && "$existing_ver" != unknown && "$cask_ver" != unknown ]]; then
          info "Versions differ — 1Password's built-in auto-updater keeps the app current regardless of brew."
        fi
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

# ── Step 4: Clone private repo (and pull latest if it already exists) ────────
log "[4/4] Clone or update private environment repo"
if [[ -d "$TARGET/.git" ]]; then
  info "Existing repo at $TARGET — pulling latest..."
  info "Remote:"
  git -C "$TARGET" remote -v 2>&1 | sed 's/^/        /'
  info "HEAD before: $(git -C "$TARGET" log -1 --oneline 2>&1)"
  git -C "$TARGET" pull --ff-only
  ok "HEAD after:  $(git -C "$TARGET" log -1 --oneline)"
elif [[ -d "$TARGET" ]]; then
  err "$TARGET exists but isn't a git repo. Remove it and re-run."
  exit 1
else
  info "Cloning $PRIVATE_REPO"
  info "Destination: $TARGET"
  mkdir -p "$(dirname "$TARGET")"
  git clone "$PRIVATE_REPO" "$TARGET"
  ok "Clone complete: $(git -C "$TARGET" log -1 --oneline)"
fi

log "Handoff to private bootstrap.sh"
info "Running: bash $TARGET/bootstrap.sh"
exec bash "$TARGET/bootstrap.sh"
