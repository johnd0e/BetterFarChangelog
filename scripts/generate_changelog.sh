#!/bin/bash
set -euo pipefail

TAG="$1"
OUTPUT_FILE="$2"
COMPARE_BASE="${UPSTREAM_COMPARE_BASE:-https://github.com/FarGroup/FarManager/compare}"
COMMIT_BASE="${UPSTREAM_COMMIT_BASE:-https://github.com/FarGroup/FarManager/commit}"

echo "[generate_changelog.sh] TAG=$TAG"

# Find the immediately preceding tag.
# sort -rV handles all tag formats correctly (numeric, semver, mixed).
echo "[generate_changelog.sh] Looking for previous tag..."
PREV_TAG=$(git tag --list 'builds/*' --sort=version:refname \
  | sort -rV \
  | awk -v tag="$TAG" 'found { print; exit } $0 == tag { found = 1 }') || {
    echo "::error::[generate_changelog.sh] Failed to determine previous tag for $TAG"
    exit 1
}
echo "[generate_changelog.sh] Previous tag: ${PREV_TAG:-none}"

echo "[generate_changelog.sh] Building commit list..."
if [ -n "$PREV_TAG" ]; then
    COMMITS=$(git log "${PREV_TAG}..${TAG}" --no-merges \
      --pretty=format:"* %s ([%h]($COMMIT_BASE/%H))") || {
        echo "::error::[generate_changelog.sh] git log failed for range ${PREV_TAG}..${TAG}"
        exit 1
    }
fi

echo "[generate_changelog.sh] Writing output file..."
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
    echo "_First tracked release._"
    echo ""
    echo "No previous build available \u2014 a compare link cannot be generated yet."
    echo ""
  fi
} > "$OUTPUT_FILE" || {
    echo "::error::[generate_changelog.sh] Failed to write output file $OUTPUT_FILE"
    exit 1
}

echo "[generate_changelog.sh] Done. Wrote $(wc -l < "$OUTPUT_FILE") line(s)."
