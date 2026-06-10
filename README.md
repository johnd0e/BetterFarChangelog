# BetterFarChangelog

Automated changelog generator and GitHub Releases publisher for [FarManager](https://github.com/FarGroup/FarManager) builds.

This repository monitors `FarGroup/FarManager` for new `builds/*` tags, generates release notes with compare links, and publishes GitHub Releases.

## Repository structure

```
.github/workflows/monitor.yml   — scheduled / manual workflow
scripts/process_tags.sh         — orchestration: fetch, find unreleased, publish
scripts/generate_changelog.sh   — generate release notes for one tag
README.md
LICENSE
```

The working branch is `automation`. It must be set as the **default branch** (GitHub runs scheduled workflows only from the default branch). It is an **orphan branch** — contains only workflow files, not FarManager source.

## Tag format

Upstream tags follow the pattern `builds/NNNN` (e.g. `builds/6695`). Releases in this repository use the same tag name.

## Workflow modes

### Auto mode (schedule / workflow_dispatch without `start_tag`)

- Fetches upstream `master` and all tags
- Compares `builds/*` tags against existing GitHub Releases in this repo
- Publishes all unreleased tags in ascending order, up to `MAX_BUILDS_PER_RUN` (default: **10**) per run
- If there are more unreleased tags than the limit, the next scheduled run picks up where this one left off
- Stops on first error; safe to rerun

### Manual mode (`workflow_dispatch` with `start_tag`)

- Starts from the specified tag, skips already-released ones
- Respects `limit` input (overrides `MAX_BUILDS_PER_RUN` if non-zero)
- Useful for backfilling or retrying after a failure

## Workflow triggers

| Trigger | Behavior |
|---|---|
| `schedule` (daily 00:00 UTC) | auto mode |
| `workflow_dispatch` without `start_tag` | auto mode |
| `workflow_dispatch` with `start_tag` | manual mode from that tag |
| `push` to `automation` | auto mode (smoke test) |

## Manual dispatch inputs

| Input | Default | Description |
|---|---|---|
| `start_tag` | _(empty)_ | Start tag for manual mode. Empty = auto mode. |
| `limit` | `0` | Max builds this run. `0` = use `MAX_BUILDS_PER_RUN`. |

## Configuration

`MAX_BUILDS_PER_RUN` is defined in `monitor.yml` under `env:`. Default is `10`. Change it there to adjust how many builds are published per scheduled run.

## Release notes format

Each release body contains:
1. Tag as heading
2. Previous build tag
3. **Compare link**: `https://github.com/FarGroup/FarManager/compare/<prev>...<current>`
4. Per-commit list with short hash linked to upstream commit page

## Setup

### 1. Create the `automation` branch as an orphan

```bash
git clone https://github.com/johnd0e/BetterFarChangelog.git
cd BetterFarChangelog
git checkout --orphan automation
git rm -rf .
# copy .github/ and scripts/
git add .
git commit -m "chore: init automation branch"
git push origin automation
```

Set `automation` as default branch: **Settings → Branches**.

### 2. Enable workflow write permissions

**Settings → Actions → General → Workflow permissions → Read and write permissions**

## Local debugging

```bash
git clone https://github.com/johnd0e/BetterFarChangelog.git
cd BetterFarChangelog
git remote add upstream https://github.com/FarGroup/FarManager.git
git fetch upstream master --force
git fetch upstream --tags --force

# Auto mode (publishes unreleased tags, needs GH_TOKEN)
GH_TOKEN=ghp_... ./scripts/process_tags.sh --auto

# Manual: publish one specific tag
GH_TOKEN=ghp_... ./scripts/process_tags.sh --start builds/6695 --limit 1
```

## Recovery after failure

1. Find the failed tag in the job log (`::error::` annotation)
2. Fix the root cause
3. Rerun workflow with `start_tag` set to the failed tag
4. Optionally set `limit=1` for a cautious first retry

## Key design decisions

- Tag pattern: `builds/*`
- Schedule runs in **auto mode** — no manual intervention needed for normal operation
- Previous tag is found per-build via `git tag | awk`, no full list kept in memory
- `MAX_BUILDS_PER_RUN=10` prevents runaway publishing on first run or after a long gap
- Processing is always ascending (oldest first); pipeline stops on first error and resumes from same tag
- No upstream commit statuses (requires upstream write access)
- `automation` is an orphan branch — no FarManager source history
