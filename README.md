# BetterFarChangelog

Automated changelog generator and GitHub Releases publisher for [FarManager](https://github.com/FarGroup/FarManager) builds.

This repository monitors `FarGroup/FarManager` for new CI tags, generates release notes, and publishes GitHub Releases under the same tag names.

## Tag format

FarManager uses tags in the format `ci/v3.0.BBBB.NNNN` where:
- `BBBB` = build number (e.g. `6695`)
- `NNNN` = CI run number (e.g. `4886`)

One build number can have multiple tags (multiple CI runs). The pipeline groups tags by build number and takes the **latest CI run** (highest `NNNN`) as the representative tag for each build.

## Repository structure

```
.github/workflows/monitor.yml   — scheduled / manual workflow
scripts/process_tags.sh         — orchestration: fetch, group, filter, publish
scripts/generate_changelog.sh   — generate release notes for one build
README.md
LICENSE
```

The working branch is `automation`. It must be set as the **default branch** (GitHub runs scheduled workflows only from the default branch).

## Workflow modes

### Dry-run (default)

Started **without** `start_tag`:
- finds the latest build
- generates its release notes
- saves to `changelog_DRY_RUN_ci_v3.0.BBBB.NNNN.md` and prints to log
- **does not push tags or create releases**

### Publish mode

Started **with** `start_tag`:
- starts from the specified tag
- iterates forward through newer builds in ascending order
- optionally limits the number of processed builds via `limit`
- skips builds that already have a GitHub Release
- stops on first error; safe to rerun from the same tag

## Workflow triggers

| Trigger | Behavior |
|---|---|
| `schedule` (daily 00:00 UTC) | dry-run |
| `workflow_dispatch` without `start_tag` | dry-run |
| `workflow_dispatch` with `start_tag` | publish |
| `push` to `automation` | dry-run (smoke test) |

## Manual inputs

| Input | Default | Description |
|---|---|---|
| `start_tag` | _(empty)_ | First tag to process. Empty = dry-run. |
| `limit` | `0` | Max builds to process. `0` = unlimited. |

## Release notes format

Each release body contains:
1. Tag name as heading
2. Previous build tag
3. **Compare link**: `https://github.com/FarGroup/FarManager/compare/<prev>...<current>`
4. Commit list with short hashes linked to upstream

## Setup

### 1. Automation branch

The `automation` branch must be an **orphan** (no FarManager source history):

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

Then set `automation` as default branch in **Settings → Branches**.

### 2. Workflow write permissions

**Settings → Actions → General → Workflow permissions → Read and write permissions**

## Local debugging

```bash
git clone https://github.com/johnd0e/BetterFarChangelog.git
cd BetterFarChangelog
git remote add upstream https://github.com/FarGroup/FarManager.git
git fetch upstream --tags --force

# Dry-run (no GH_TOKEN needed)
./scripts/process_tags.sh

# Publish one build
GH_TOKEN=ghp_... ./scripts/process_tags.sh --start ci/v3.0.6695.4886 --limit 1
```

## Recovery after failure

1. Find the failed tag in the job log (the `::error::` annotation)
2. Fix the root cause
3. Rerun workflow with `start_tag` set to the failed tag
4. Optionally set `limit=1` for a cautious first retry

## Key design decisions

- Tag pattern is `ci/v*`; tags are grouped by build number (`BBBB`), latest CI run per build is used
- Processing is always in ascending build order
- Dry-run is the default; explicit `start_tag` is required to publish
- Pipeline stops on first error and resumes safely from the same tag
- No upstream commit statuses (requires upstream write access not available)
- `automation` is an orphan branch — contains only workflow files, not FarManager source
