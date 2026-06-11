#!/bin/bash
# Args:
#   $1 = TAG           e.g. builds/6695
#   $2 = OUTPUT_FILE
# Env:
#   PREV_TAG           previous builds/* tag (may be empty)
#   UPSTREAM_DIR       path to master checkout (default: ./upstream)
#
# Exit codes:
#   0  success
#   1  unexpected error
#   2  not yet implemented
set -euo pipefail

trap 'echo "::error::[generate_changelog.sh] Unexpected error on line $LINENO (exit $?). TAG=${TAG:-?}"' ERR

TAG="$1"
OUTPUT_FILE="$2"
PREV_TAG="${PREV_TAG:-}"
UPSTREAM_DIR="${UPSTREAM_DIR:-./upstream}"
COMPARE_BASE="${UPSTREAM_COMPARE_BASE:-https://github.com/FarGroup/FarManager/compare}"
COMMIT_BASE="${UPSTREAM_COMMIT_BASE:-https://github.com/FarGroup/FarManager/commit}"

COMMITS=""
if [ -n "$PREV_TAG" ]; then
    COMMITS=$(git -C "$UPSTREAM_DIR" log "${PREV_TAG}..${TAG}" --no-merges \
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
    echo "_First tracked release \u2014 no previous build available._"
    echo ""
  fi
} > "$OUTPUT_FILE"

echo "[generate_changelog.sh] $TAG: $(wc -l < "$OUTPUT_FILE") line(s), prev=${PREV_TAG:-none}."

# TODO: real changelog processing not yet implemented
echo "::warning::[generate_changelog.sh] Changelog processing not yet implemented."
exit 2
