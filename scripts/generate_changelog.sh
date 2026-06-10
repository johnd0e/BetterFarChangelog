#!/bin/bash
# Args:
#   $1 = TAG           e.g. builds/6695
#   $2 = OUTPUT_FILE
#   $3 = ALL_TAGS      newline-separated sorted list of builds/* tags (passed from process_tags.sh)
set -euo pipefail

trap 'echo "::error::[generate_changelog.sh] Unexpected error on line $LINENO (exit $?). TAG=${TAG:-?}"' ERR

TAG="$1"
OUTPUT_FILE="$2"
ALL_TAGS="$3"
COMPARE_BASE="${UPSTREAM_COMPARE_BASE:-https://github.com/FarGroup/FarManager/compare}"
COMMIT_BASE="${UPSTREAM_COMMIT_BASE:-https://github.com/FarGroup/FarManager/commit}"

echo "[generate_changelog.sh] TAG=$TAG"

# Find previous tag. ALL_TAGS is already in a variable — no pipe, no SIGPIPE.
PREV_TAG=$(echo "$ALL_TAGS" | awk -v tag="$TAG" 'found { print; exit } $0 == tag { found = 1 }')
echo "[generate_changelog.sh] Previous tag: ${PREV_TAG:-none}"

COMMITS=""
if [ -n "$PREV_TAG" ]; then
    echo "[generate_changelog.sh] git log ${PREV_TAG}..${TAG}"
    COMMITS=$(git log "${PREV_TAG}..${TAG}" --no-merges \
      --pretty=format:"* %s ([%h]($COMMIT_BASE/%H))")
    echo "[generate_changelog.sh] Commits: $(echo "$COMMITS" | grep -c '^\*' || true)"
fi

echo "[generate_changelog.sh] Writing output..."
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

echo "[generate_changelog.sh] Done. $(wc -l < "$OUTPUT_FILE") line(s) written."
