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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --start)
            START_TAG="${2:-}"
            DRY_RUN=false
            shift 2
            ;;
        --limit)
            LIMIT="${2:-0}"
            shift 2
            ;;
        *)
            error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
    error "--limit must be a non-negative integer. Got: $LIMIT"
    exit 1
fi

section "Collecting upstream tags"
ALL_TAGS=$(git tag --list 'builds/*' --sort=version:refname)

if [ -z "$ALL_TAGS" ]; then
    info "No tags matching 'builds/*' were found after fetch. Nothing to do."
    exit 0
fi

TOTAL=$(echo "$ALL_TAGS" | wc -l | tr -d ' ')
info "Found $TOTAL tag(s)."

if $DRY_RUN; then
    LAST_TAG=$(echo "$ALL_TAGS" | tail -n 1)
    WORK_TAGS="$LAST_TAG"
    info "Dry-run mode: only the latest tag will be processed: $LAST_TAG"
else
    if [ -z "$START_TAG" ]; then
        error "Publish mode requires --start <tag>."
        exit 1
    fi

    WORK_TAGS=$(echo "$ALL_TAGS" | awk -v start="$START_TAG" 'found || $0 == start { found = 1; print }')

    if [ -z "$WORK_TAGS" ]; then
        error "Tag '$START_TAG' was not found in the upstream tag list."
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
            FILTERED="$FILTERED$TAG\n"
        fi
    done

    WORK_TAGS=$(printf "%b" "$FILTERED" | sed '/^$/d')

    if [ -z "$WORK_TAGS" ]; then
        info "All selected tags already have releases. Nothing to do."
        exit 0
    fi

    NEW_COUNT=$(echo "$WORK_TAGS" | wc -l | tr -d ' ')
    info "Will process $NEW_COUNT new tag(s). Already released and skipped: $SKIPPED."
fi

PROCESSED=0

for TAG in $WORK_TAGS; do
    section "[$TAG]"

    CHANGELOG_FILE=$(mktemp /tmp/changelog_XXXXXX.md)

    info "[$TAG] Generating changelog..."
    if ! ./scripts/generate_changelog.sh "$TAG" "$CHANGELOG_FILE"; then
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
        if ! git push origin "refs/tags/$TAG:refs/tags/$TAG"; then
            warn "[$TAG] Tag push failed or the tag already exists in origin. Continuing."
        fi

        info "[$TAG] Creating GitHub release..."
        if ! RELEASE_OUTPUT=$(gh release create "$TAG" \
                --title "FarManager $TAG" \
                --notes-file "$CHANGELOG_FILE" 2>&1); then
            error "[$TAG] Failed to create GitHub release: $RELEASE_OUTPUT"
            rm -f "$CHANGELOG_FILE"
            info "Retry by running the workflow manually with start_tag=$TAG."
            exit 1
        fi

        info "[$TAG] Release published: $RELEASE_OUTPUT"
        PROCESSED=$((PROCESSED + 1))
    fi

    rm -f "$CHANGELOG_FILE"
done

section "Done"
if $DRY_RUN; then
    info "Dry-run completed. No tags were pushed and no releases were created."
else
    info "Published $PROCESSED release(s)."
fi
