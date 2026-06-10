#!/bin/bash
# Tags format: ci/v3.0.BBBB.NNNN
# Multiple tags can share the same build number BBBB (different CI runs).
# We group by BBBB and take the latest tag per build (highest NNNN).
# Releases are named after the latest tag of each build.
set -euo pipefail

error()   { echo "::error::$*"; echo "ERROR: $*" >&2; }
warn()    { echo "::warning::$*"; echo "WARNING: $*"; }
info()    { echo "$*"; }
section() { info ""; info "========================================="; info "$*"; }

DRY_RUN=true
START_TAG=""
LIMIT=0
TAG_PATTERN="${TAG_PATTERN:-ci/v*}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --start)   START_TAG="${2:-}"; DRY_RUN=false; shift 2 ;;
        --limit)   LIMIT="${2:-0}"; shift 2 ;;
        *) error "Unknown argument: $1"; exit 1 ;;
    esac
done

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
    error "--limit must be a non-negative integer. Got: $LIMIT"
    exit 1
fi

section "Collecting upstream tags matching '$TAG_PATTERN'"

# Read all matching tags sorted ascending into a variable (avoids SIGPIPE).
ALL_TAGS=$(git tag --list "$TAG_PATTERN" --sort=version:refname)

if [ -z "$ALL_TAGS" ]; then
    info "No tags matching '$TAG_PATTERN' found after fetch. Nothing to do."
    exit 0
fi

TOTAL=$(echo "$ALL_TAGS" | wc -l | tr -d ' ')
info "Found $TOTAL tag(s) matching '$TAG_PATTERN'."

# Build the list of representative tags: one per unique build number (BBBB),
# taking the last (highest NNNN) tag of each group.
# Tag format: ci/v3.0.BBBB.NNNN
# We sort ascending by version, so the last occurrence of each BBBB wins.
REP_TAGS=$(echo "$ALL_TAGS" | awk '
{
    # Extract build number: 4th dot-separated field of the version part
    # ci/v3.0.BBBB.NNNN -> split on . -> [ci/v3, 0, BBBB, NNNN]
    n = split($0, a, ".")
    bbbb = a[n-1]   # second-to-last component = build number
    last[bbbb] = $0 # overwrite: last one wins (ascending sort)
}
END {
    for (b in last) print last[b]
}' | sort -t. -k3 -V)

REP_TOTAL=$(echo "$REP_TAGS" | wc -l | tr -d ' ')
info "Unique build numbers: $REP_TOTAL"

if $DRY_RUN; then
    LAST_TAG=$(echo "$REP_TAGS" | tail -n 1)
    WORK_TAGS="$LAST_TAG"
    info "Dry-run mode: processing latest build only: $LAST_TAG"
else
    if [ -z "$START_TAG" ]; then
        error "Publish mode requires --start <tag>."
        exit 1
    fi

    # Slice from START_TAG onwards (inclusive)
    WORK_TAGS=$(echo "$REP_TAGS" | awk -v start="$START_TAG" 'found || $0 == start { found = 1; print }')

    if [ -z "$WORK_TAGS" ]; then
        error "Tag '$START_TAG' not found among representative tags."
        info "Available representative tags (last 10):"
        echo "$REP_TAGS" | tail -n 10
        exit 1
    fi

    if [ "$LIMIT" -gt 0 ]; then
        WORK_TAGS=$(echo "$WORK_TAGS" | head -n "$LIMIT")
    fi

    RELEASED_TAGS=$(gh release list --limit 1000 --json tagName --jq '.[].tagName' 2>/dev/null || true)
    FILTERED=""
    SKIPPED=0
    for TAG in $WORK_TAGS; do
        if echo "$RELEASED_TAGS" | grep -qx "$TAG"; then
            info "[skip] $TAG — release already exists."
            SKIPPED=$((SKIPPED + 1))
        else
            FILTERED="$FILTERED$TAG
"
        fi
    done
    WORK_TAGS=$(echo "$FILTERED" | sed '/^$/d')

    if [ -z "$WORK_TAGS" ]; then
        info "All selected tags already have releases. Nothing to do."
        exit 0
    fi

    NEW_COUNT=$(echo "$WORK_TAGS" | wc -l | tr -d ' ')
    info "Will process $NEW_COUNT new build(s). Skipped $SKIPPED already released."
fi

PROCESSED=0

for TAG in $WORK_TAGS; do
    section "[$TAG]"

    CHANGELOG_FILE=$(mktemp /tmp/changelog_XXXXXX.md)

    info "[$TAG] Generating changelog..."
    if ! ./scripts/generate_changelog.sh "$TAG" "$CHANGELOG_FILE" "$REP_TAGS"; then
        error "[$TAG] generate_changelog.sh failed."
        rm -f "$CHANGELOG_FILE"
        exit 1
    fi

    if [ ! -s "$CHANGELOG_FILE" ]; then
        error "[$TAG] generate_changelog.sh produced an empty file."
        rm -f "$CHANGELOG_FILE"
        exit 1
    fi

    if $DRY_RUN; then
        DRY_OUT="changelog_DRY_RUN_${TAG//\//_}.md"
        cp "$CHANGELOG_FILE" "$DRY_OUT"
        info "[$TAG] Dry-run output saved to $DRY_OUT"
        section "[$TAG] Dry-run preview"
        cat "$CHANGELOG_FILE"
    else
        info "[$TAG] Pushing tag to origin..."
        git push origin "refs/tags/$TAG:refs/tags/$TAG" || \
            warn "[$TAG] Tag push failed or tag already exists in origin."

        info "[$TAG] Creating GitHub release..."
        if ! RELEASE_OUTPUT=$(gh release create "$TAG" \
                --title "FarManager $TAG" \
                --notes-file "$CHANGELOG_FILE" 2>&1); then
            error "[$TAG] Failed to create release: $RELEASE_OUTPUT"
            rm -f "$CHANGELOG_FILE"
            info "Retry: re-run workflow with start_tag=$TAG"
            exit 1
        fi
        info "[$TAG] Published: $RELEASE_OUTPUT"
        PROCESSED=$((PROCESSED + 1))
    fi

    rm -f "$CHANGELOG_FILE"
done

section "Done"
if $DRY_RUN; then
    info "Dry-run complete. No releases were created."
else
    info "Published $PROCESSED release(s)."
fi
