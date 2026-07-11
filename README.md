# env_bootstrap

Public bootstrap for fresh machines. Handles prerequisites (Homebrew +
1Password on macOS; distro packages on Linux), then clones the private
[environment](https://github.com/rmferrer/environment) repo and hands off to
its `bootstrap.sh` for chezmoi.

## What it does

- **macOS**: installs Homebrew + 1Password desktop app + 1Password CLI, opens
  1Password, pauses for you to sign in and enable BOTH the SSH agent and CLI
  integration toggles in Settings → Developer.
- **Linux (devboxes)**: installs git/curl/ca-certificates via apt. **No
  1Password** — nothing in the dotfiles reads `op://` secrets (the public
  signing keys are inlined in `.chezmoidata.toml`), and both SSH auth and git
  commit signing go through the agent forwarded from your laptop, so connect
  with `ssh -A`. This also sidesteps `op` CLI's standalone sign-in, which
  can't handle Duo/security-key MFA on the work account.
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
- **Linux, any user (root or not)**: installs distro packages, verifies the
  forwarded SSH agent (`ssh -A` from your laptop), clones the private repo,
  runs chezmoi. Answer `true` to "Is this a work machine?" on devboxes.
- **macOS, root**: refuses. Log in as your regular account.
