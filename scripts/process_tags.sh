#!/bin/bash
# Orchestrates the full pipeline: fetch upstream tags, find unreleased ones,
# generate changelogs and publish GitHub Releases in ascending version order.
# Tags are numeric: builds/NNNN (e.g. builds/6676).
# Exits on the first failure so the next manual run resumes from the same tag.
set -euo pipefail

# Emit a GitHub Actions error annotation visible directly in the workflow summary.
error() { echo "::error::$*"; echo "ERROR: $*" >&2; }
warn()  { echo "::warning::$*"; }
info()  { echo "$*"; }

# --- Collect upstream tags ---
info "Collecting upstream tags matching 'builds/*'..."
UPSTREAM_TAGS=$(git tag --list 'builds/*' --sort=version:refname)

if [ -z "$UPSTREAM_TAGS" ]; then
    info "No tags matching 'builds/*' found. Nothing to do."
    exit 0
fi

TAG_COUNT=$(echo "$UPSTREAM_TAGS" | wc -l | tr -d ' ')
info "Found $TAG_COUNT upstream tag(s). Checking which are already released..."

# Compare against existing GitHub Releases (more reliable than local git tags:
# a previous run may have pushed a tag but crashed before creating the release).
RELEASED_TAGS=$(gh release list --limit 1000 --json tagName --jq '.[].tagName' 2>/dev/null || true)

NEW_TAGS=""
for TAG in $UPSTREAM_TAGS; do
    if echo "$RELEASED_TAGS" | grep -qx "$TAG"; then
        continue
    fi
    NEW_TAGS="$NEW_TAGS$TAG
"
done
NEW_TAGS=$(echo "$NEW_TAGS" | sed '/^$/d')

if [ -z "$NEW_TAGS" ]; then
    info "All upstream tags already have releases. Nothing to do."
    exit 0
fi

NEW_COUNT=$(echo "$NEW_TAGS" | wc -l | tr -d ' ')
info "$NEW_COUNT new tag(s) to process: $(echo "$NEW_TAGS" | tr '\n' ' ')"

# --- Process each new tag in ascending order ---
PROCESSED=0

for TAG in $NEW_TAGS; do
    info ""
    info "========================================="
    info "[$TAG] Processing..."

    # --- Changelog generation ---
    CHANGELOG_FILE="$(mktemp /tmp/changelog_XXXXXX.md)"
    info "[$TAG] Generating changelog..."
    if ! ./scripts/generate_changelog.sh "$TAG" "$CHANGELOG_FILE" 2>&1; then
        error "[$TAG] generate_changelog.sh failed. See output above."
        rm -f "$CHANGELOG_FILE"
        exit 1
    fi

    if [ ! -s "$CHANGELOG_FILE" ]; then
        error "[$TAG] generate_changelog.sh produced an empty file."
        rm -f "$CHANGELOG_FILE"
        exit 1
    fi

    info "[$TAG] Changelog ready ($(wc -l < "$CHANGELOG_FILE") lines)."

    # --- Push the tag into our own origin so the release can reference it ---
    info "[$TAG] Pushing tag to origin..."
    if ! git push origin "refs/tags/$TAG:refs/tags/$TAG" 2>&1; then
        warn "[$TAG] Could not push tag (may already exist in origin). Continuing."
    fi

    # --- Create GitHub Release ---
    info "[$TAG] Creating GitHub Release..."
    if ! RELEASE_OUTPUT=$(gh release create "$TAG" \
        --title "FarManager $TAG" \
        --notes-file "$CHANGELOG_FILE" 2>&1); then
        error "[$TAG] 'gh release create' failed: $RELEASE_OUTPUT"
        rm -f "$CHANGELOG_FILE"
        info "To retry, re-trigger the workflow manually or push to the automation branch."
        exit 1
    fi

    info "[$TAG] Release published: $RELEASE_OUTPUT"
    PROCESSED=$((PROCESSED + 1))
    rm -f "$CHANGELOG_FILE"
done

info ""
info "========================================="
info "Done. $PROCESSED new release(s) published."
