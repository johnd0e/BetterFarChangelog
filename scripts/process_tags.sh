#!/bin/bash
set -euo pipefail

error()   { echo "::error::$*"; echo "ERROR: $*" >&2; }
warn()    { echo "::warning::$*"; echo "WARNING: $*"; }
info()    { echo "$*"; }
section() { info ""; info "========================================="; info "$*"; }

DRY_RUN=true
START_TAG=""
LIMIT=0

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

section "Collecting upstream tags matching 'builds/*'"

ALL_TAGS=$(git tag --list 'builds/*' --sort=version:refname)

if [ -z "$ALL_TAGS" ]; then
    error "No tags matching 'builds/*' found. Make sure upstream was fetched correctly."
    exit 1
fi

TOTAL=$(echo "$ALL_TAGS" | wc -l | tr -d ' ')
info "Found $TOTAL tag(s)."

if $DRY_RUN; then
    LAST_TAG=$(echo "$ALL_TAGS" | tail -n 1)
    WORK_TAGS="$LAST_TAG"
    info "Dry-run mode: processing latest tag only: $LAST_TAG"
else
    if [ -z "$START_TAG" ]; then
        error "Publish mode requires --start <tag>."
        exit 1
    fi

    WORK_TAGS=$(echo "$ALL_TAGS" | awk -v start="$START_TAG" 'found || $0 == start { found = 1; print }')

    if [ -z "$WORK_TAGS" ]; then
        error "Tag '$START_TAG' not found. Available tags (last 10):"
        echo "$ALL_TAGS" | tail -n 10 >&2
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
    info "Will process $NEW_COUNT new tag(s). Skipped $SKIPPED already released."
fi

PROCESSED=0

for TAG in $WORK_TAGS; do
    section "[$TAG]"

    CHANGELOG_FILE=$(mktemp /tmp/changelog_XXXXXX.md)

    info "[$TAG] Generating changelog..."
    # Pass ALL_TAGS via environment variable to preserve newlines
    if ! ALL_TAGS="$ALL_TAGS" ./scripts/generate_changelog.sh "$TAG" "$CHANGELOG_FILE"; then
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
            info "Retry: rerun workflow with start_tag=$TAG"
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
