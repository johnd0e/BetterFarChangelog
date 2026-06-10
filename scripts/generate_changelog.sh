#!/bin/bash
set -euo pipefail

# Trap any unexpected error and print the line number
trap 'echo "::error::[generate_changelog.sh] Unexpected error on line $LINENO (exit code $?). TAG=${TAG:-?}"' ERR

TAG="$1"
OUTPUT_FILE="$2"
COMPARE_BASE="${UPSTREAM_COMPARE_BASE:-https://github.com/FarGroup/FarManager/compare}"
COMMIT_BASE="${UPSTREAM_COMMIT_BASE:-https://github.com/FarGroup/FarManager/commit}"

echo "[generate_changelog.sh] TAG=$TAG"

# Find the immediately preceding tag.
# We read ALL tags into a variable first to avoid SIGPIPE when awk exits early
# from a still-running git process (exit code 141 under set -e).
echo "[generate_changelog.sh] Looking for previous tag..."
ALL_TAGS=$(git tag --list 'builds/*' --sort=-version:refname)
PREV_TAG=$(echo "$ALL_TAGS" | awk -v tag="$TAG" 'found { print; exit } $0 == tag { found = 1 }')
echo "[generate_changelog.sh] Previous tag: ${PREV_TAG:-none}"

# COMMITS must be initialised before the conditional block (set -u requirement)
COMMITS=""

if [ -n "$PREV_TAG" ]; then
    echo "[generate_changelog.sh] Running git log ${PREV_TAG}..${TAG}..."
    COMMITS=$(git log "${PREV_TAG}..${TAG}" --no-merges \
      --pretty=format:"* %s ([%h]($COMMIT_BASE/%H))")
    COUNT=$(echo "$COMMITS" | grep -c '^\*' || true)
    echo "[generate_changelog.sh] Commits found: $COUNT"
fi

echo "[generate_changelog.sh] Writing $OUTPUT_FILE..."
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
    echo "_First tracked release \u2014 no previous build available._"
    echo ""
  fi
} > "$OUTPUT_FILE"

echo "[generate_changelog.sh] Done. Wrote $(wc -l < "$OUTPUT_FILE") line(s)."
