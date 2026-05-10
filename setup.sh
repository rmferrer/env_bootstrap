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

pause() {
  printf '\n==> %s\n    Press ENTER to continue.\n' "$1"
  read -r _ </dev/tty
}

load_brew_env() {
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
  [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
}

# ── Homebrew ──────────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
load_brew_env

# ── Per-OS 1Password setup ────────────────────────────────────────────────────
case "$OS" in
  Darwin)
    if ! brew list --cask 1password &>/dev/null; then
      echo "==> Installing 1Password desktop app..."
      brew install --cask 1password
    fi
    if ! command -v op &>/dev/null; then
      echo "==> Installing 1Password CLI..."
      brew install --cask 1password-cli
    fi
    open -a 1Password || true
    pause "In 1Password: sign in, then Settings → Developer → enable BOTH
    • Use the SSH agent
    • Integrate with 1Password CLI"
    if ! op account list &>/dev/null; then
      echo "ERROR: 'op account list' failed. Is CLI integration enabled?" >&2
      exit 1
    fi
    ;;
  Linux)
    if ! command -v op &>/dev/null; then
      echo "==> Installing 1Password CLI..."
      brew install 1password-cli
    fi
    if ! op account list &>/dev/null; then
      echo "==> Adding 1Password account (have ready: domain, email, secret key, master password)"
      op account add </dev/tty
    fi
    echo "==> Signing in to 1Password..."
    eval "$(op signin </dev/tty)"
    if ! ssh-add -l &>/dev/null; then
      echo "ERROR: no SSH keys in agent. Reconnect with 'ssh -A' to forward your 1Password agent." >&2
      exit 1
    fi
    ;;
  *)
    echo "Unsupported OS: $OS" >&2
    exit 1
    ;;
esac

# ── Clone private repo ────────────────────────────────────────────────────────
if [[ ! -d "$TARGET" ]]; then
  echo "==> Cloning private environment repo..."
  mkdir -p "$(dirname "$TARGET")"
  git clone "$PRIVATE_REPO" "$TARGET"
fi

echo "==> Handing off to $TARGET/bootstrap.sh"
exec "$TARGET/bootstrap.sh"
