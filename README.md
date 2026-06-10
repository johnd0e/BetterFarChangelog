# BetterFarChangelog

Automated changelog generator and GitHub Releases publisher for [FarManager](https://github.com/FarGroup/FarManager) builds.

This repository monitors `FarGroup/FarManager` for new tags matching `builds/*`, generates release notes, and publishes GitHub Releases under the same tag names.

## Repository structure

```
.github/workflows/monitor.yml   — scheduled / manual workflow
scripts/process_tags.sh         — orchestration: fetch, filter, generate, publish
scripts/generate_changelog.sh   — generate release notes for one tag
README.md
LICENSE
```

The working branch is `automation`. It should be set as the **default branch**, because GitHub only runs scheduled workflows from the default branch.

This repository does **not** need to be an official GitHub fork of `FarGroup/FarManager`. A fork was created (`johnd0e/FarManager`) as a mirror but the automation lives here.

## How monitoring works

- Monitoring is **tag-based**, not branch-based.
- Tags follow the pattern `builds/NNNN` (e.g. `builds/6676`).
- Tags are fetched from upstream using `git fetch upstream --tags --force`.
- Tags are always processed in **ascending numeric order** (oldest first).
- The pipeline stops on the first failure; restarting from the same tag is safe.

## Workflow modes

### Dry-run (default)

If the workflow is started **without** `start_tag`, it runs a dry-run:

- finds the latest `builds/*` tag
- generates release notes for that tag only
- saves the output to `changelog_DRY_RUN_builds_NNNN.md` in the workspace
- prints the Markdown to the job log
- **does not push tags or create releases**

This is the safest mode for testing and verifying `generate_changelog.sh` output.

### Publish mode

If the workflow is started **with** `start_tag`, it switches to publish mode:

- starts from the specified tag
- iterates forward through newer tags in ascending order
- optionally limits the number of processed tags via `limit` (0 = unlimited)
- skips tags that already have a GitHub Release in this repository
- on the first failure: prints a clear error, stops, and recommends the retry command

## Workflow triggers

| Trigger | Behavior |
|---|---|
| `schedule` (daily 00:00 UTC) | dry-run |
| `workflow_dispatch` without `start_tag` | dry-run |
| `workflow_dispatch` with `start_tag` | publish mode |
| `push` to `automation` branch | dry-run (for quick smoke-test of script changes) |

## Manual launch inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `start_tag` | no | _(empty)_ | First tag to process. Empty triggers dry-run. |
| `limit` | no | `0` | Max tags to process. `0` = unlimited. |

Examples:

- `start_tag=builds/6676` — publish from `builds/6676` onwards, no limit
- `start_tag=builds/6676`, `limit=3` — publish at most 3 tags starting from `builds/6676`

## Release notes format

Each release body contains:

1. Current tag as heading
2. Name of the previous tag
3. **Compare link**: `https://github.com/FarGroup/FarManager/compare/<prev>...<current>`
4. Per-commit list with short hash linked to the upstream commit page

The compare link opens the standard GitHub diff view between two adjacent build tags.

## Setup

### 1. Create the `automation` branch as an orphan

The `automation` branch must be created as an **orphan** (no shared history with FarManager source):

```bash
git clone https://github.com/johnd0e/BetterFarChangelog.git
cd BetterFarChangelog
git checkout --orphan automation
git rm -rf .
# copy .github/ and scripts/ here
git add .
git commit -m "chore: init automation branch"
git push origin automation
```

Then in **Settings → Branches** set `automation` as the default branch.

### 2. Enable write permissions for workflows

**Settings → Actions → General → Workflow permissions** → **Read and write permissions**

Required for pushing tags and creating GitHub Releases.

## Local debugging

You can run scripts locally against a cloned FarManager:

```bash
# Clone and fetch upstream tags
git clone https://github.com/johnd0e/BetterFarChangelog.git
cd BetterFarChangelog
git remote add upstream https://github.com/FarGroup/FarManager.git
git fetch upstream --tags --force

# Dry-run for the latest tag
./scripts/process_tags.sh

# Dry-run for a specific tag (still no release created)
./scripts/process_tags.sh --dry-run  # same as above

# Publish 1 tag (requires GH_TOKEN)
GH_TOKEN=ghp_... ./scripts/process_tags.sh --start builds/6676 --limit 1
```

With `act`:

```bash
act workflow_dispatch --secret-file .secrets
```

`.secrets` file:

```
GITHUB_TOKEN=ghp_...
```

## Upstream commit statuses

Posting commit statuses to `FarGroup/FarManager` requires collaborator Write access on that repository. This feature is **not implemented** and not planned unless upstream access is granted.

## Recovery after a failed run

1. Identify the failed tag from the job log (the `::error::` annotation).
2. Fix the root cause.
3. Re-run the workflow manually with `start_tag` set to the failed tag.
4. Optionally set `limit=1` to process just that one tag first.

## Key design decisions

- Tag-based (not commit/branch-based) monitoring
- Ascending sequential processing (later changelogs depend on earlier ones)
- Dry-run is the default; releases are created only in explicit publish mode
- Stopping on the first error is intentional — the pipeline resumes safely from the same tag
- No upstream commit statuses (requires upstream write access)
- `automation` is an orphan branch — it contains only workflow files, not FarManager source
- The `main` branch in this repository is unused; only `automation` matters for the workflow
