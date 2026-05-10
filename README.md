# env_bootstrap

Public bootstrap entrypoint for fresh machines. Solves the chicken-and-egg
problem of needing SSH to clone the private [environment](https://github.com/rmferrer/environment) repo.

## What it does

1. Installs Homebrew
2. **macOS**: installs the 1Password desktop app + CLI, opens 1Password, pauses
   for the user to sign in and enable the SSH agent + CLI integration in
   Settings → Developer.
3. **Linux**: installs the 1Password CLI, runs `op account add` + `op signin`.
   Relies on SSH agent forwarding (`ssh -A`) from your local machine for the
   git clone.
4. Clones `git@github.com:rmferrer/environment.git` to `~/code/env`.
5. `exec`s `~/code/env/bootstrap.sh` for chezmoi + Brewfile + mise setup.

## Run it

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/rmferrer/env_bootstrap/master/bootstrap.sh)"
```
