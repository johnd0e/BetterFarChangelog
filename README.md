# BetterFarChangelog

Automated changelog generator and GitHub Releases publisher for [FarManager](https://github.com/FarGroup/FarManager) upstream builds.

Monitors the upstream repository for new `builds/*` tags and publishes human-friendly release notes as GitHub Releases in this fork.

---

## How It Works

1. A scheduled GitHub Actions workflow runs daily at midnight UTC (and on every push to the `automation` branch).
2. The workflow fetches all upstream tags matching `builds/*`.
3. It compares them against existing GitHub Releases in **this** repository.
4. For every tag that has no corresponding release yet, it calls `scripts/generate_changelog.sh` to produce Markdown release notes.
5. Tags are processed in ascending version order so that each changelog can reference previous ones.
6. A GitHub Release is created for each processed tag.
7. CI commit statuses (pending / success / error) are posted to the upstream commit SHA so progress is visible at a glance.
8. On any failure, processing stops and can be re-triggered manually or by pushing to this branch.

> **Releases in this fork are completely independent of the upstream repository.** GitHub Releases are a per-repository feature and are never propagated to the original project.

---

## Repository Structure

```
.github/
  workflows/
    monitor.yml          # Main GitHub Actions workflow
scripts/
  process_tags.sh        # Core orchestration: fetch, diff, loop, CI statuses
  generate_changelog.sh  # Placeholder — implement your changelog logic here
LICENSE
README.md
```

---

## Setup

### 1. Fork or mirror the upstream repository

You can either:
- Use GitHub's **Fork** button on the upstream repository, or
- Create an empty repository and mirror it manually:
  ```bash
  git clone --bare https://github.com/FarGroup/FarManager.git
  cd FarManager.git
  git push --mirror https://github.com/johnd0e/BetterFarChangelog.git
  ```

### 2. Create the `automation` branch

The branch that holds this workflow **must be the default branch** of your repository, because GitHub only runs scheduled workflows from the default branch.

```bash
git checkout --orphan automation   # Start a branch with no history
git rm -rf .                       # Clear the working tree
# Copy workflow files here, then:
git add .
git commit -m "chore: init automation branch"
git push origin automation
```

In **Settings → Branches**, set `automation` as the default branch.

### 3. Allow workflow write permissions

Go to **Settings → Actions → General → Workflow permissions** and select **Read and write permissions**. This is required for pushing tags and creating releases.

### 4. Configure the upstream URL

Edit `.github/workflows/monitor.yml` and set the `UPSTREAM_REPO` environment variable to the URL of the repository you want to monitor.

---

## Triggering the Workflow

| Trigger | How |
|---|---|
| **Scheduled** | Runs automatically every day at 00:00 UTC |
| **Push to branch** | Push any commit to the `automation` branch |
| **Manual** | Go to **Actions → Release Builds Monitor → Run workflow** |

On manual dispatch the workflow runs immediately without any required inputs.

---

## Local Debugging with `act`

[nektos/act](https://github.com/nektos/act) lets you run the full workflow locally inside Docker, without making noise commits.

```bash
# Install (macOS / Linux)
brew install act

# Simulate a manual dispatch
act workflow_dispatch --secret-file .secrets

# .secrets file (never commit this):
# GITHUB_TOKEN=ghp_yourtoken...
```

The VS Code extension **GitHub Local Actions** (by Sanjula Ganepola) provides a GUI for the same functionality.

To debug without waiting for a real upstream update, point `UPSTREAM_REPO` at a private test repository and push fake `builds/*` tags there:

```bash
git tag builds/v0.0.1
git push my-test-upstream --tags
```

---

## Implementing Changelog Generation

The file `scripts/generate_changelog.sh` is intentionally left as a placeholder. It receives two arguments:

```bash
./scripts/generate_changelog.sh <TAG> <OUTPUT_FILE>
# Example: ./scripts/generate_changelog.sh builds/6000 changelog.md
```

Inside the script you have access to the full Git history (because `actions/checkout` uses `fetch-depth: 0`) and can use any tool available on `ubuntu-latest`, including Python, Node.js, or custom CLI utilities.

Suggested approaches:
- Parse raw `git log` output between two adjacent tags using `--pretty=format:`.
- Use an LLM API to summarise commit messages into human-readable prose.
- Apply conventional-commit parsing (`feat:`, `fix:`, etc.) if the upstream follows that convention.

---

## CI Commit Statuses

The workflow posts commit statuses directly to the upstream commit SHA using the GitHub Statuses API:

- 🟡 **pending** — changelog is being generated
- ✅ **success** — release was created successfully
- ❌ **error** — something went wrong; re-trigger manually

These statuses appear on the upstream repository's commit history, even though the workflow runs in a completely different repository. No write access to upstream is required — only a valid `GITHUB_TOKEN` with `statuses: write` permission on *your* fork.

---

## License

MIT © 2026 johnd0e
