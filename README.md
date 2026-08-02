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

Download the reviewed revision, verify its SHA-256 digest, and only then run
it. This deliberately avoids executing a mutable branch or URL shortener.

```bash
tmp="$(mktemp "${TMPDIR:-/tmp}/env-bootstrap.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
  --output "$tmp" \
  https://raw.githubusercontent.com/rmferrer/env_bootstrap/daf41a6e8cc0229c8d89719292afc50ff838d108/setup.sh
expected=3b72b2559d73f235e6c0d31dac3439fa475a2e267a08605e2b1a437694211075
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$tmp" | awk '{print $1}')"
fi
[ "$actual" = "$expected" ] || { echo "bootstrap checksum mismatch" >&2; exit 1; }
/bin/bash "$tmp"
```

The script branches on what it finds:

- **macOS, regular user**: installs Homebrew + 1Password app/CLI, pauses for
  you to enable SSH agent + CLI integration, clones the private repo, runs
  chezmoi.
- **Linux, any user (root or not)**: installs distro packages, verifies the
  forwarded SSH agent (`ssh -A` from your laptop), clones the private repo,
  runs chezmoi. chezmoi asks two independent profile questions — "Enable the
  work profile?" and "Enable the personal profile?" — answer `true`/`false`
  per machine (devboxes: work `true`, personal `false`).
- **macOS, root**: refuses. Log in as your regular account.

## Security model

- The bootstrap verifies the reviewed Homebrew installer entrypoint before
  executing it. Package payload verification remains the responsibility of
  Homebrew and the platform package managers.
- An existing `~/code/env` checkout must point at the expected GitHub repo, and
  its `bootstrap.sh` must match the committed `HEAD` version before handoff.
- Linux setup uses a forwarded SSH agent only long enough to authenticate the
  private clone. A compromised remote host can use a forwarded agent while the
  SSH connection is alive, so only bootstrap trusted devboxes and disconnect
  when setup is complete.
- The pinned setup revision and digest must be updated together after reviewing
  future bootstrap changes.
