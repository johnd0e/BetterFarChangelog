#!/bin/bash
# Orchestrates the full pipeline: fetch upstream tags, find unreleased ones,
# generate changelogs and publish GitHub Releases in ascending version order.
# Exits on the first failure so the next manual run resumes from the same tag.
set -euo pipefail

echo "Fetching upstream tags..."
git remote add upstream "$UPSTREAM_REPO" 2>/dev/null || true
git fetch upstream --tags --force

# List all upstream tags matching 'builds/*', sorted oldest-first (v:refname = version sort)
UPSTREAM_TAGS=$(git ls-remote --tags --sort=v:refname upstream "refs/tags/builds/*" \
  | awk -F'refs/tags/' '{print $2}' \
  | grep -v '\^{}')

if [ -z "$UPSTREAM_TAGS" ]; then
    echo "No tags matching 'builds/*' found in upstream. Nothing to do."
    exit 0
fi

# Fetch the list of already-published releases from THIS repository.
# Using the Releases API is more reliable than checking local git tags,
# because a previous run may have pushed a tag but failed before creating the release.
RELEASED_TAGS=$(gh release list --limit 1000 --json tagName --jq '.[].tagName' 2>/dev/null || true)

PROCESSED=0

for TAG in $UPSTREAM_TAGS; do
    if echo "$RELEASED_TAGS" | grep -qx "$TAG"; then
        echo "[$TAG] Release already exists. Skipping."
        continue
    fi

    echo "=========================================="
    echo "[$TAG] New unreleased tag found. Processing..."

    # Resolve the commit SHA that this tag points to (needed for CI status API).
    # '^{}' dereferences annotated tags to the underlying commit object.
    COMMIT_SHA=$(git ls-remote upstream "refs/tags/$TAG^{}" | awk '{print $1}')
    if [ -z "$COMMIT_SHA" ]; then
        # Lightweight tag: SHA is the tag ref itself
        COMMIT_SHA=$(git ls-remote upstream "refs/tags/$TAG" | awk '{print $1}')
    fi

    # --- CI Status: pending ---
    if [ -n "$COMMIT_SHA" ]; then
        echo "[$TAG] Setting CI status to 'pending' on $COMMIT_SHA"
        gh api --method POST \
          -H "Accept: application/vnd.github+json" \
          "repos/{owner}/{repo}/statuses/$COMMIT_SHA" \
          -f state='pending' \
          -f description='Generating release notes...' \
          -f context='BetterFarChangelog' || true
    fi

    # --- Changelog generation ---
    CHANGELOG_FILE="$(mktemp /tmp/changelog_XXXXXX.md)"
    echo "[$TAG] Calling generate_changelog.sh..."
    # The script must exit non-zero on failure; set -e will then stop this script.
    ./scripts/generate_changelog.sh "$TAG" "$CHANGELOG_FILE"

    # --- Push the tag to origin so the release can be attached to it ---
    echo "[$TAG] Pushing tag to origin..."
    git push origin "refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null || true

    # --- Create GitHub Release ---
    echo "[$TAG] Creating GitHub Release..."
    if gh release create "$TAG" \
        --title "Build $TAG" \
        --notes-file "$CHANGELOG_FILE"; then

        echo "[$TAG] Release created successfully."

        # --- CI Status: success ---
        if [ -n "$COMMIT_SHA" ]; then
            gh api --method POST \
              -H "Accept: application/vnd.github+json" \
              "repos/{owner}/{repo}/statuses/$COMMIT_SHA" \
              -f state='success' \
              -f description='Release published successfully!' \
              -f context='BetterFarChangelog' || true
        fi

        PROCESSED=$((PROCESSED + 1))
        rm -f "$CHANGELOG_FILE"
    else
        echo "[$TAG] ERROR: gh release create failed."

        # --- CI Status: error ---
        if [ -n "$COMMIT_SHA" ]; then
            gh api --method POST \
              -H "Accept: application/vnd.github+json" \
              "repos/{owner}/{repo}/statuses/$COMMIT_SHA" \
              -f state='error' \
              -f description='Release creation failed.' \
              -f context='BetterFarChangelog' || true
        fi

        rm -f "$CHANGELOG_FILE"
        echo "Stopping. Re-trigger the workflow manually after fixing the issue."
        exit 1
    fi
done

echo "=========================================="
echo "Done. $PROCESSED new release(s) published."
