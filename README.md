# BetterFarChangelog

Automated changelog generator and GitHub Releases publisher for [FarManager](https://github.com/FarGroup/FarManager) builds.

This repository monitors `FarGroup/FarManager` for new `builds/*` tags, generates release notes, and publishes GitHub Releases.

## Repository structure

```
.github/workflows/sync.yml      — sync origin/master and tags from upstream
.github/workflows/release.yml   — generate changelogs and publish GitHub Releases
scripts/process_tags.sh         — orchestration: find unreleased tags, publish
scripts/generate_changelog.sh   — generate release notes for one tag
README.md
LICENSE
```

## Branches

- **`automation`** — default branch. Contains only workflow files and scripts. All scheduled workflows run from here.
- **`master`** — mirror of `FarGroup/FarManager`. Kept identical to upstream; never modified manually.

## Workflow overview

### 1. `sync.yml` — Sync upstream

- Triggers: daily schedule (00:00 UTC), `workflow_dispatch`.
- Checks out `master`, fetches `FarGroup/FarManager` master and all tags, resets and force-pushes to `origin/master`.
- No release logic here.

### 2. `release.yml` — Publish releases

- Triggers: after `sync.yml` completes successfully, `workflow_dispatch`, `push` to `automation`.
- Does **not** add any external git remote. Works only with `johnd0e/BetterFarChangelog`.
- Checks out `automation` branch (scripts) into workspace root.
- Checks out `master` branch (tags + commits) into `./upstream`.
- Finds all `builds/*` tags that have no corresponding GitHub Release.
- Publishes up to `MAX_BUILDS_PER_RUN` (default: 10) releases per run.
- The next scheduled run picks up where this one left off.

## Configuration

`MAX_BUILDS_PER_RUN` is set in `release.yml` under `env:`. Default: `10`.

## Workflow triggers

| Trigger | Workflow | Behavior |
|---|---|---|
| `schedule` daily 00:00 UTC | `sync.yml` | Sync master + tags from upstream |
| `sync.yml` success | `release.yml` | Auto-publish new releases |
| `workflow_dispatch` | both | Manual run |
| `push` to `automation` | `release.yml` | Smoke test |

## Manual dispatch inputs (`release.yml`)

| Input | Default | Description |
|---|---|---|
| `start_tag` | _(empty)_ | Start from this tag. Empty = auto mode. |
| `limit` | `0` | Max builds this run. `0` = use `MAX_BUILDS_PER_RUN`. |

## Release notes format

Each release body contains:
1. Tag as heading
2. Previous build tag
3. **Compare link**: `https://github.com/FarGroup/FarManager/compare/<prev>...<current>`
4. Per-commit list with short hash linked to upstream

## Setup

### 1. Ensure `automation` is the default branch

**Settings → Branches → Default branch** → set to `automation`.

### 2. Enable workflow write permissions

**Settings → Actions → General → Workflow permissions → Read and write permissions**

### 3. Initial sync

If `master` branch does not exist yet, run `sync.yml` manually first:

**Actions → Sync upstream master → Run workflow**

Then run `release.yml` manually with an appropriate `start_tag`.

## Recovery after failure

1. Find the failed tag in the job log (`::error::` annotation)
2. Fix the root cause
3. Run `release.yml` manually with `start_tag` set to the failed tag
4. Optionally set `limit=1` for a cautious first retry

## Local debugging

```bash
git clone https://github.com/johnd0e/BetterFarChangelog.git
cd BetterFarChangelog

# Simulate what release.yml does:
mkdir upstream
git clone https://github.com/johnd0e/BetterFarChangelog.git upstream
cd upstream && git checkout master && cd ..

GH_TOKEN=ghp_... GH_REPO=johnd0e/BetterFarChangelog \
  UPSTREAM_DIR=./upstream \
  ./scripts/process_tags.sh --auto
```

## Key design decisions

- `master` is a pure upstream mirror — never modified directly
- `automation` is the default branch — required for scheduled workflows
- `release.yml` adds no external remotes — no `gh` CLI confusion between repos
- `MAX_BUILDS_PER_RUN=10` caps output per run; daily schedule catches up naturally
- Ascending order, stops on first error, safe to resume from same tag
