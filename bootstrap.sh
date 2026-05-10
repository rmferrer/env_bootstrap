#!/usr/bin/env bash
# Public bootstrap for fresh machines.
# Installs Homebrew + 1Password, pauses for the user to authenticate,
# then clones the private environment repo and hands off to its bootstrap.sh.
#
# Run via:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rmferrer/env_bootstrap/master/bootstrap.sh)"

set -euo pipefail

PRIVATE_REPO="git@github.com:rmferrer/environment.git"
TARGET="$HOME/code/env"
OS="$(uname -s)"

pause() {
  printf '\n==> %s\n    Press ENTER to continue.\n' "$1"
  read -r _ </dev/tty
}

load_brew_env() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
}

install_homebrew() {
  if command -v brew &>/dev/null; then return; fi
  echo "==> Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew_env
}

setup_macos() {
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
    echo "ERROR: 'op account list' failed. Is CLI integration enabled in 1Password?" >&2
    exit 1
  fi
}

setup_linux() {
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
    pause "No SSH keys in agent. If on a remote host, reconnect with 'ssh -A' so the
    1Password SSH agent on your laptop is forwarded. Then re-run this script."
    exit 1
  fi
}

clone_and_handoff() {
  if [[ ! -d "$TARGET" ]]; then
    echo "==> Cloning private environment repo..."
    mkdir -p "$(dirname "$TARGET")"
    git clone "$PRIVATE_REPO" "$TARGET"
  else
    echo "==> $TARGET already exists; skipping clone."
  fi
  echo "==> Handing off to $TARGET/bootstrap.sh"
  exec "$TARGET/bootstrap.sh"
}

main() {
  install_homebrew
  load_brew_env
  case "$OS" in
    Darwin) setup_macos ;;
    Linux)  setup_linux ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
  esac
  clone_and_handoff
}

main "$@"
