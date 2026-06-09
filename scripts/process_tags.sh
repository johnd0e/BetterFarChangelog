#!/bin/bash
# Orchestrates the full pipeline: fetch upstream tags, find unreleased ones,
# generate changelogs and publish GitHub Releases in ascending version order.
# Tags are numeric: builds/NNNN (e.g. builds/6676).
# Exits on the first failure so the next manual run resumes from the same tag.
set -euo pipefail

echo "Fetching upstream tags from $UPSTREAM_REPO ..."
git remote add upstream "$UPSTREAM_REPO" 2>/dev/null || true
git fetch upstream --tags --force

# List all upstream tags matching 'builds/*', sorted oldest-first.
# 'v:refname' applies version sort, which correctly orders numeric suffixes
# (builds/6600 < builds/6610 < builds/6676).
UPSTREAM_TAGS=$(git ls-remote --tags --sort=v:refname upstream "refs/tags/builds/*" \
  | awk -F'refs/tags/' '{print $2}' \
  | grep -v '\^{}')

if [ -z "$UPSTREAM_TAGS" ]; then
    echo "No tags matching 'builds/*' found in upstream. Nothing to do."
    exit 0
fi

# Fetch the list of already-published releases from THIS repository.
# Comparing against existing Releases (not local git tags) is intentional:
# a previous run may have pushed a tag but crashed before creating the release.
RELEASED_TAGS=$(gh release list --limit 1000 --json tagName --jq '.[].tagName' 2>/dev/null || true)

PROCESSED=0

for TAG in $UPSTREAM_TAGS; do
    if echo "$RELEASED_TAGS" | grep -qx "$TAG"; then
        echo "[$TAG] Release already exists. Skipping."
        continue
    fi

    echo "=========================================="
    echo "[$TAG] New unreleased tag found. Processing..."

    # Resolve the upstream commit SHA this tag points to.
    # Try the peeled (^{}) form first — that handles annotated tags.
    # Fall back to the plain ref for lightweight tags.
    COMMIT_SHA=$(git ls-remote upstream "refs/tags/$TAG^{}" | awk '{print $1}')
    if [ -z "$COMMIT_SHA" ]; then
        COMMIT_SHA=$(git ls-remote upstream "refs/tags/$TAG" | awk '{print $1}')
    fi

    # --- CI Status: pending ---
    # We post the status to the UPSTREAM repo's commit so it appears in FarManager's history.
    # Note: GITHUB_TOKEN has statuses:write scope only for our own repo by default.
    # For upstream commit statuses to work, a PAT with repo scope must be stored
    # as a repository secret named UPSTREAM_STATUS_TOKEN and substituted here.
    if [ -n "$COMMIT_SHA" ]; then
        echo "[$TAG] Setting CI status to 'pending' on upstream commit $COMMIT_SHA"
        gh api --method POST \
          -H "Accept: application/vnd.github+json" \
          "/repos/$UPSTREAM_OWNER/$UPSTREAM_REPO_NAME/statuses/$COMMIT_SHA" \
          -f state='pending' \
          -f description='Generating release notes...' \
          -f context='BetterFarChangelog' \
          --hostname github.com || echo "[$TAG] Warning: could not set pending status (token may lack scope)."
    fi

    # --- Changelog generation ---
    CHANGELOG_FILE="$(mktemp /tmp/changelog_XXXXXX.md)"
    echo "[$TAG] Calling generate_changelog.sh..."
    # generate_changelog.sh must exit non-zero on failure;
    # set -e will then abort this script immediately.
    ./scripts/generate_changelog.sh "$TAG" "$CHANGELOG_FILE"

    # --- Push the tag into our own origin so the release can reference it ---
    echo "[$TAG] Pushing tag to origin..."
    git push origin "refs/tags/$TAG:refs/tags/$TAG" || echo "[$TAG] Warning: tag already exists in origin."

    # --- Create GitHub Release in our repository ---
    echo "[$TAG] Creating GitHub Release..."
    if gh release create "$TAG" \
        --title "FarManager Build $TAG" \
        --notes-file "$CHANGELOG_FILE"; then

        echo "[$TAG] Release created successfully."

        if [ -n "$COMMIT_SHA" ]; then
            gh api --method POST \
              -H "Accept: application/vnd.github+json" \
              "/repos/$UPSTREAM_OWNER/$UPSTREAM_REPO_NAME/statuses/$COMMIT_SHA" \
              -f state='success' \
              -f description='BetterFarChangelog release published!' \
              -f context='BetterFarChangelog' \
              --hostname github.com || true
        fi

        PROCESSED=$((PROCESSED + 1))
        rm -f "$CHANGELOG_FILE"
    else
        echo "[$TAG] ERROR: gh release create failed."

        if [ -n "$COMMIT_SHA" ]; then
            gh api --method POST \
              -H "Accept: application/vnd.github+json" \
              "/repos/$UPSTREAM_OWNER/$UPSTREAM_REPO_NAME/statuses/$COMMIT_SHA" \
              -f state='error' \
              -f description='BetterFarChangelog: release creation failed.' \
              -f context='BetterFarChangelog' \
              --hostname github.com || true
        fi

        rm -f "$CHANGELOG_FILE"
        echo "Stopping. Fix the issue and re-trigger the workflow manually (or push to automation branch)."
        exit 1
    fi
done

echo "=========================================="
echo "Done. $PROCESSED new release(s) published."
