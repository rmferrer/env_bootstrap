# env_bootstrap

Public bootstrap for fresh machines. Handles auth setup (Homebrew, 1Password
sign-in, SSH agent + CLI integration), then clones the private
[environment](https://github.com/rmferrer/environment) repo and hands off to
its `bootstrap.sh` for chezmoi.

## What it does

- **macOS**: installs Homebrew + 1Password desktop app + 1Password CLI, opens
  1Password, pauses for you to sign in and enable BOTH the SSH agent and CLI
  integration toggles in Settings → Developer.
- **Linux**: installs Homebrew + 1Password CLI, runs `op account add` + `op signin`.
  Relies on SSH agent forwarding (`ssh -A`) from your laptop for the git clone.
- Clones `git@github.com:rmferrer/environment.git` to `~/code/env`.
- `exec`s `~/code/env/bootstrap.sh` (which runs chezmoi to apply dotfiles,
  Brewfile, mise toolchains).

## Run it

```sh
/bin/bash -c "$(curl -fsSL https://bit.ly/rmferrer_env_bootstrap)"
```

That's the only command. The script branches on what it finds:

- **macOS, regular user**: installs Homebrew + 1Password app/CLI, pauses for
  you to enable SSH agent + CLI integration, clones the private repo, runs
  chezmoi.
- **Linux, non-root user**: installs Homebrew + 1Password CLI, runs
  `op account add` / `op signin`, clones via forwarded SSH agent, runs
  chezmoi.
- **Linux, root (e.g., fresh server with only root access)**: creates a
  non-root user (default `rmferrer`, override with `INIT_USER=<name>`) with
  sudo + SSH access (keys copied from `/root/.ssh/authorized_keys`) and
  prints the reconnect instructions. After reconnecting as the new user with
  `ssh -A`, run the same one-liner again — same URL, same script.
- **macOS, root**: refuses. Log in as your regular account.
