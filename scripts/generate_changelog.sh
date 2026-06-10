#!/bin/bash
set -euo pipefail

TAG="$1"
OUTPUT_FILE="$2"
COMPARE_BASE="${UPSTREAM_COMPARE_BASE:-https://github.com/FarGroup/FarManager/compare}"
COMMIT_BASE="${UPSTREAM_COMMIT_BASE:-https://github.com/FarGroup/FarManager/commit}"

echo "[generate_changelog.sh] TAG=$TAG"

# Find the immediately preceding tag.
# sort -rV handles all tag name formats (numeric, semver, mixed).
# Empty result is normal for the very first tag — not an error.
echo "[generate_changelog.sh] Looking for previous tag..."
PREV_TAG=$(git tag --list 'builds/*' --sort=version:refname \
  | sort -rV \
  | awk -v tag="$TAG" 'found { print; exit } $0 == tag { found = 1 }')
echo "[generate_changelog.sh] Previous tag: ${PREV_TAG:-none}"

# Init COMMITS so set -u doesn't complain when PREV_TAG is empty
COMMITS=""

if [ -n "$PREV_TAG" ]; then
    echo "[generate_changelog.sh] Building commit list for ${PREV_TAG}..${TAG}..."
    COMMITS=$(git log "${PREV_TAG}..${TAG}" --no-merges \
      --pretty=format:"* %s ([%h]($COMMIT_BASE/%H))") || {
        echo "::error::[generate_changelog.sh] git log failed for range ${PREV_TAG}..${TAG}"
        exit 1
    }
    echo "[generate_changelog.sh] Commits found: $(echo "$COMMITS" | grep -c '^' || true)"
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
    echo "_First tracked release — no previous build available._"
    echo ""
  fi
} > "$OUTPUT_FILE" || {
    echo "::error::[generate_changelog.sh] Failed to write output file $OUTPUT_FILE"
    exit 1
}

echo "[generate_changelog.sh] Done. Wrote $(wc -l < "$OUTPUT_FILE") line(s)."
