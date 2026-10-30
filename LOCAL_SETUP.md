# Local installation and upstream updates

TradingAgents is installed directly in this project. The reviewed starting point is
v0.7.1, upstream commit `c4544913a14ed3df5f1ed7b9e8483270ce20682a`.
The remote `upstream` fetches TauricResearch/TradingAgents; pushing to it is disabled.
The remote `origin` is your fork, https://github.com/raym79/TradingAgents.git.
`main` tracks `origin/main`; `local/main` is the local setup branch. Keep upstream
changes on review branches and merge them into the fork through pull requests.
`deployment/upstream.json` records the reviewed source revision; `uv.lock` records
dependency versions and artifact hashes. Keep both in version control.

## Install and run on Windows

Python 3.12.10 is pinned in `.python-version`. From PowerShell in this directory:

```powershell
.\scripts\manage.ps1 Install
.\scripts\manage.ps1 Verify
# Configure your provider credentials in .env before an analysis.
.\scripts\manage.ps1 Run
# CLI help, with no provider requests:
.\scripts\manage.ps1 Run --help
```

If Windows blocks the script, use a process-scoped invocation:
`powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manage.ps1 Install`.
No persistent execution-policy change is needed.

`.tools` holds pinned uv 0.9.5; `.venv` holds this project's package and development
dependencies. No global Python package installation is needed. Installation uses
`uv sync --locked`, which rejects stale dependency metadata rather than silently
resolving new versions. It may download the pinned Python if unavailable.
`Run` stores reports, caches, and memory inside ignored `.runtime/`.
The underlying CLI can also be invoked directly as
`.\.venv\Scripts\tradingagents.exe` (uses upstream's default state paths).
Secrets in `.env` and `.env.enterprise` are ignored; never add them with `git add -f`.
Live analyses require provider authentication and may incur provider charges.

## Check and prepare updates

```powershell
.\scripts\manage.ps1 Updates
# Example only: choose a new tag shown by Updates when one becomes available.
.\scripts\manage.ps1 PrepareUpdate -Ref v0.7.2
```

`Updates` refreshes Git refs and reports new main commits, the latest stable tag,
and a comparison link. It does not modify source code, the lockfile, or the environment.
Prefer stable release tags; use a full SHA only when you intentionally need an
unreleased fix. Do not automatically pull main into a working installation.

`PrepareUpdate` requires a clean working tree, creates `update/upstream-<sha>`,
merges the selected revision without committing, refreshes the lockfile while
retaining existing compatible versions, and runs dependency checks, lint, offline
tests, and CLI help. Only after they pass does it update the reviewed baseline.
Review `git diff HEAD` and the upstream changelog before committing the merge.
If conflicts occur, resolve them and rerun `uv lock` using `.tools\Scripts\uv.exe`,
then `Verify`; update the manifest to the chosen revision only after verification.
Use `git merge --abort` to cancel an unfinished merge. Verification failure leaves
the update branch and diagnostics available for inspection; nothing is promoted.

After review, commit the update branch, push it to `origin`, and open a PR to the
fork's `main`. Start each new update from the latest fork main:

```powershell
git switch main
git pull --ff-only origin main
# Run PrepareUpdate, review its diff, and commit the merge before pushing.
git push -u origin HEAD
```

After the PR passes CI and is merged, switch back to `main`, pull with
`--ff-only`, and run `Install` and `Verify` to sync the active environment.

For dependency-only updates, create a separate branch and run
`.\.tools\Scripts\uv.exe lock --upgrade`, then `Verify`. Review the `uv.lock` diff.
Keep source and dependency upgrades separate when possible. Do not regenerate the
lockfile during normal installation or CI. Upgrade Python and uv deliberately in
a reviewed change, updating both the installer and CI's tool version together.

## CI, hosting, and promotion

`.github/workflows/locked-ci.yml` verifies the lockfile, dependency consistency,
lint, offline tests and CLI help on Windows and Linux with Python 3.12.10.
It installs a wheel rather than the editable source package. Actions use immutable
commit pins and a read-only token. Upstream's workflows remain available as well.
No live provider keys or brokerage credentials are needed for these checks.

`.github/workflows/upstream-watch.yml` compares the reviewed baseline with upstream
weekly and on manual dispatch. Its Actions summary contains the version, commit
count and comparison link. It neither merges nor deploys changes and does not send
custom notifications. GitHub schedules run on the default branch; Actions must be
enabled, including on forks, and GitHub may disable inactive schedules.

The workflows belong in [your fork](https://github.com/raym79/TradingAgents).
Push changes to `origin`; retain `upstream` only for fetching original releases.
The weekly schedule becomes eligible after the workflow reaches the fork's default
branch and Actions is enabled. Inspect results under the fork's Actions tab.

On your repository, require the `locked (ubuntu-latest)` and
`locked (windows-latest)` checks and PR review on the default branch. Keep
automatic merging disabled for upstream updates. Confirm both hosted checks pass
before promoting an update; a local Windows check alone does not certify Linux.

For deployment, promote an exact reviewed Git SHA with its lockfile into a separate
environment, run a paper/research smoke analysis using that environment's secrets,
and record the SHA with outputs. This project has no deployment target yet, so
automated production deployment is intentionally not configured.

Rollback by checking out a known-good deployment SHA in a separate checkout and
running `Install`; for a published shared branch, revert the update PR rather than
rewriting history. Runtime outputs and persistent memory are separate from Git:
back them up before upgrades that may change their format.

## References

- [Upstream installation and configuration](https://github.com/TauricResearch/TradingAgents#installation-and-cli)
- [uv locking and syncing](https://docs.astral.sh/uv/concepts/projects/sync/)
- [GitHub Actions security practices](https://docs.github.com/en/actions/reference/security/secure-use)
