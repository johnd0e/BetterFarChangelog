#!/bin/bash
set -euo pipefail

TAG="$1"
OUTPUT_FILE="$2"
COMPARE_BASE="${UPSTREAM_COMPARE_BASE:-https://github.com/FarGroup/FarManager/compare}"
COMMIT_BASE="${UPSTREAM_COMMIT_BASE:-https://github.com/FarGroup/FarManager/commit}"

# Find the immediately preceding tag
PREV_TAG=$(git tag --list 'builds/*' --sort=version:refname \
  | tac \
  | awk -v tag="$TAG" 'found { print; exit } $0 == tag { found = 1 }')

{
  echo "# $TAG"
  echo ""

  if [ -n "$PREV_TAG" ]; then
    echo "Previous build: \`$PREV_TAG\`"
    echo ""
    echo "**[Compare $PREV_TAG...$TAG]($COMPARE_BASE/$PREV_TAG...$TAG)**"
    echo ""
    echo "Commits:"
    echo ""
    git log "${PREV_TAG}..${TAG}" --no-merges \
      --pretty=format:"* %s ([%h]($COMMIT_BASE/%H))"
    echo ""
  else
    echo "_First tracked release._"
    echo ""
    echo "No previous build available — a compare link cannot be generated yet."
    echo ""
  fi
} > "$OUTPUT_FILE"

echo "[generate_changelog.sh] $TAG: wrote $(wc -l < "$OUTPUT_FILE") line(s); previous tag: ${PREV_TAG:-none}"
