#!/usr/bin/env bash
# init_user.sh — Run AS ROOT on a fresh Linux box to create a non-root user
# with sudo + SSH access (keys copied from root's authorized_keys).
# After this completes, log out, SSH back in as the new user with `-A`,
# and run setup.sh.
#
# Usage (default username 'rmferrer'):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rmferrer/env_bootstrap/master/init_user.sh)"
#
# Custom username via env var:
#   INIT_USER=alice /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rmferrer/env_bootstrap/master/init_user.sh)"

set -euo pipefail

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    [OK]   %s\n' "$*"; }
err()  { printf '\nERROR: %s\n' "$*" >&2; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  err "init_user.sh must run as root."
  exit 1
fi
if [[ "$(uname -s)" != "Linux" ]]; then
  err "init_user.sh is for Linux only."
  exit 1
fi

NEW_USER="${INIT_USER:-rmferrer}"

log "init_user.sh — bootstrap a non-root user"
info "Target user:  $NEW_USER"
info "Hostname:     $(hostname)"
info "OS release:   $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"

# ── Create user ───────────────────────────────────────────────────────────────
log "[1/4] User account"
if id "$NEW_USER" &>/dev/null; then
  skip_msg="User '$NEW_USER' already exists with UID $(id -u "$NEW_USER")"
  info "[skip] $skip_msg"
else
  info "useradd -m -s /bin/bash $NEW_USER"
  useradd -m -s /bin/bash "$NEW_USER"
  ok "Created $NEW_USER (UID $(id -u "$NEW_USER"))"
fi

# ── Sudo group ────────────────────────────────────────────────────────────────
log "[2/4] Sudo group"
if getent group sudo &>/dev/null; then
  SUDO_GROUP=sudo
elif getent group wheel &>/dev/null; then
  SUDO_GROUP=wheel
else
  err "Neither 'sudo' nor 'wheel' group exists on this system."
  err "Install sudo first (apt install sudo / yum install sudo) and re-run."
  exit 1
fi
info "Group: $SUDO_GROUP"
if id -nG "$NEW_USER" | tr ' ' '\n' | grep -qx "$SUDO_GROUP"; then
  info "[skip] $NEW_USER is already in $SUDO_GROUP"
else
  usermod -aG "$SUDO_GROUP" "$NEW_USER"
  ok "Added $NEW_USER to $SUDO_GROUP"
fi

# ── Passwordless sudo (so scripts don't hang on sudo password prompts) ────────
log "[3/4] Passwordless sudo"
SUDOERS_FILE="/etc/sudoers.d/90-${NEW_USER}"
if [[ -f "$SUDOERS_FILE" ]]; then
  info "[skip] $SUDOERS_FILE already exists"
else
  echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
  chmod 440 "$SUDOERS_FILE"
  ok "Wrote $SUDOERS_FILE"
fi

# ── SSH authorized_keys (copy from root so the user can SSH in immediately) ──
log "[4/4] SSH authorized_keys"
ROOT_KEYS="/root/.ssh/authorized_keys"
USER_SSH_DIR="/home/$NEW_USER/.ssh"
USER_KEYS="$USER_SSH_DIR/authorized_keys"
if [[ -f "$USER_KEYS" ]]; then
  info "[skip] $USER_KEYS already exists ($(wc -l <"$USER_KEYS") line(s))"
elif [[ -f "$ROOT_KEYS" ]]; then
  info "Copying $ROOT_KEYS → $USER_KEYS"
  mkdir -p "$USER_SSH_DIR"
  cp "$ROOT_KEYS" "$USER_KEYS"
  chown -R "$NEW_USER:$NEW_USER" "$USER_SSH_DIR"
  chmod 700 "$USER_SSH_DIR"
  chmod 600 "$USER_KEYS"
  ok "Copied $(wc -l <"$USER_KEYS") key(s); owner=$NEW_USER, perms 700/600"
else
  err "$ROOT_KEYS not found. Add your public key to $USER_KEYS manually,"
  err "or you won't be able to SSH in as $NEW_USER."
  exit 1
fi

log "Done!"
info "Next steps (from your laptop):"
info "  1. Disconnect from this root session."
info "  2. SSH back in as $NEW_USER WITH agent forwarding so your 1Password"
info "     SSH agent on the laptop authenticates the private repo clone:"
info "       ssh -A $NEW_USER@$(hostname)"
info "  3. Run the regular bootstrap:"
info "       /bin/bash -c \"\$(curl -fsSL https://bit.ly/rmferrer_env_bootstrap)\""
