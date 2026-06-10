#!/bin/bash
# Process builds/* tags and publish GitHub Releases.
#
# Modes:
#   --auto              Find all unreleased tags, publish up to MAX_BUILDS_PER_RUN (default 10).
#   --start <tag>       Publish starting from <tag>. --limit N overrides MAX_BUILDS_PER_RUN.
set -euo pipefail

error()   { echo "::error::$*"; echo "ERROR: $*" >&2; }
warn()    { echo "::warning::$*"; echo "WARNING: $*"; }
info()    { echo "$*"; }
section() { echo ""; echo "========================================="; echo "$*"; }

MODE=""
START_TAG=""
LIMIT=0
MAX_BUILDS_PER_RUN="${MAX_BUILDS_PER_RUN:-10}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)  MODE="auto"; shift ;;
        --start) MODE="start"; START_TAG="${2:-}"; shift 2 ;;
        --limit) LIMIT="${2:-0}"; shift 2 ;;
        *) error "Unknown argument: $1"; exit 1 ;;
    esac
done

if [ -z "$MODE" ]; then
    error "Usage: process_tags.sh --auto | --start <tag> [--limit N]"
    exit 1
fi

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
    error "--limit must be a non-negative integer. Got: $LIMIT"
    exit 1
fi

if [ "$LIMIT" -eq 0 ]; then
    EFFECTIVE_LIMIT="$MAX_BUILDS_PER_RUN"
else
    EFFECTIVE_LIMIT="$LIMIT"
fi

section "Collecting released tags"
RELEASED_TAGS=$(gh release list --limit 10000 --json tagName --jq '.[].tagName' 2>/dev/null || true)
RELEASED_COUNT=$(echo "$RELEASED_TAGS" | grep -c '.' || true)
info "Already released: $RELEASED_COUNT"

section "Collecting upstream tags"
ALL_TAGS=$(git tag --list 'builds/*' --sort=version:refname)

if [ -z "$ALL_TAGS" ]; then
    error "No tags matching 'builds/*' found."
    exit 1
fi

# Filter unreleased: awk lookup against RELEASED_TAGS, fully in-memory, no pipes to head
filter_unreleased() {
    local tags="$1"
    # Build a lookup of released tags, then print only those not in it
    echo "$tags" | awk -v released="$RELEASED_TAGS" '
        BEGIN { while ((getline line < "/dev/stdin") > 0) released_set[line]=1 }
        !released_set[$0]
    ' || true
}

if [ "$MODE" = "auto" ]; then
    UNRELEASED=$(echo "$ALL_TAGS" | awk -v released="$RELEASED_TAGS" '
        BEGIN { n=split(released, a, "\n"); for(i=1;i<=n;i++) rel[a[i]]=1 }
        !rel[$0]
    ')

    if [ -z "$UNRELEASED" ]; then
        info "No new tags to release."
        exit 0
    fi

    # Apply limit in-memory
    WORK_TAGS=$(echo "$UNRELEASED" | awk -v lim="$EFFECTIVE_LIMIT" 'NR<=lim')
    COUNT=$(echo "$WORK_TAGS" | wc -l | tr -d ' ')
    info "Found $COUNT unreleased tag(s) to process (limit: $EFFECTIVE_LIMIT)."
else
    ALL_FROM_START=$(echo "$ALL_TAGS" | awk -v start="$START_TAG" 'found || $0 == start { found = 1; print }')

    if [ -z "$ALL_FROM_START" ]; then
        error "Tag '$START_TAG' not found among builds/* tags."
        exit 1
    fi

    UNRELEASED=$(echo "$ALL_FROM_START" | awk -v released="$RELEASED_TAGS" '
        BEGIN { n=split(released, a, "\n"); for(i=1;i<=n;i++) rel[a[i]]=1 }
        !rel[$0]
    ')

    if [ -z "$UNRELEASED" ]; then
        info "All tags from '$START_TAG' onwards are already released."
        exit 0
    fi

    WORK_TAGS=$(echo "$UNRELEASED" | awk -v lim="$EFFECTIVE_LIMIT" 'NR<=lim')
    COUNT=$(echo "$WORK_TAGS" | wc -l | tr -d ' ')
    info "Found $COUNT unreleased tag(s) starting from '$START_TAG' (limit: $EFFECTIVE_LIMIT)."
fi

PROCESSED=0

for TAG in $WORK_TAGS; do
    section "[$TAG]"

    PREV_TAG=$(echo "$ALL_TAGS" | awk -v tag="$TAG" 'prev && $0 == tag { print prev; exit } { prev = $0 }')

    CHANGELOG_FILE=$(mktemp /tmp/changelog_XXXXXX.md)

    info "[$TAG] Generating changelog (prev: ${PREV_TAG:-none})..."
    if ! PREV_TAG="$PREV_TAG" ./scripts/generate_changelog.sh "$TAG" "$CHANGELOG_FILE"; then
        error "[$TAG] generate_changelog.sh failed."
        rm -f "$CHANGELOG_FILE"
        exit 1
    fi

    if [ ! -s "$CHANGELOG_FILE" ]; then
        error "[$TAG] generate_changelog.sh produced an empty file."
        rm -f "$CHANGELOG_FILE"
        exit 1
    fi

    info "[$TAG] Pushing tag to origin..."
    git push origin "refs/tags/$TAG:refs/tags/$TAG" || \
        warn "[$TAG] Tag push failed or already exists in origin."

    info "[$TAG] Creating GitHub release..."
    if ! RELEASE_OUTPUT=$(gh release create "$TAG" \
            --title "FarManager $TAG" \
            --notes-file "$CHANGELOG_FILE" 2>&1); then
        error "[$TAG] Failed to create release: $RELEASE_OUTPUT"
        rm -f "$CHANGELOG_FILE"
        info "Retry: rerun workflow with start_tag=$TAG"
        exit 1
    fi
    info "[$TAG] Published: $RELEASE_OUTPUT"
    PROCESSED=$((PROCESSED + 1))

    rm -f "$CHANGELOG_FILE"
done

section "Done"
info "Published $PROCESSED release(s)."
