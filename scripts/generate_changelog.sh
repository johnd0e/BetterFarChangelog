#!/bin/bash
# Args:
#   $1 = TAG           e.g. builds/6695
#   $2 = OUTPUT_FILE
# Env:
#   TAGS_FILE          path to sorted builds/* tag list (written by process_tags.sh)
set -euo pipefail

trap 'echo "::error::[generate_changelog.sh] Unexpected error on line $LINENO (exit $?). TAG=${TAG:-?}"' ERR

TAG="$1"
OUTPUT_FILE="$2"
COMPARE_BASE="${UPSTREAM_COMPARE_BASE:-https://github.com/FarGroup/FarManager/compare}"
COMMIT_BASE="${UPSTREAM_COMMIT_BASE:-https://github.com/FarGroup/FarManager/commit}"

if [ -z "${TAGS_FILE:-}" ] || [ ! -f "$TAGS_FILE" ]; then
    echo "::error::[generate_changelog.sh] TAGS_FILE is not set or does not exist: '${TAGS_FILE:-}'"
    exit 1
fi

# Find previous tag by reading from file — no env var size limits, no SIGPIPE
PREV_TAG=$(awk -v tag="$TAG" 'found { print; exit } $0 == tag { found = 1 }' "$TAGS_FILE")
echo "[generate_changelog.sh] $TAG — previous: ${PREV_TAG:-none}"

COMMITS=""
if [ -n "$PREV_TAG" ]; then
    COMMITS=$(git log "${PREV_TAG}..${TAG}" --no-merges \
      --pretty=format:"* %s ([%h]($COMMIT_BASE/%H))")
fi

{
  echo "# $TAG"
  echo ""
  if [ -n "$PREV_TAG" ]; then
    echo "Previous build: \`$PREV_TAG\`"
    echo ""
    echo "**[Compare $PREV_TAG...$TAG]($COMPARE_BASE/$PREV_TAG...$TAG)**"
    echo ""
    if [ -n "$COMMITS" ]; then
      echo "Commits:"
      echo ""
      echo "$COMMITS"
      echo ""
    else
      echo "_No commits between these builds._"
      echo ""
    fi
  else
    echo "_First tracked release — no previous build available._"
    echo ""
  fi
} > "$OUTPUT_FILE"

echo "[generate_changelog.sh] Done. $(wc -l < "$OUTPUT_FILE") line(s)."
