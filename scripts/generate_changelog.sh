#!/bin/bash
# Placeholder for changelog generation logic.
# Called by process_tags.sh with:
#   $1 = TAG (e.g. "builds/6000")
#   $2 = OUTPUT_FILE (path to write Markdown into)
#
# Exit non-zero to signal failure and stop the pipeline.
set -euo pipefail

TAG="$1"
OUTPUT_FILE="$2"

# Find the previous tag of the same format for diffing
PREV_TAG=$(git ls-remote --tags --sort=-v:refname upstream "refs/tags/builds/*" \
  | awk -F'refs/tags/' '{print $2}' \
  | grep -v '\^{}' \
  | grep -A1 "^${TAG}$" | tail -n1)

{
  echo "## $TAG"
  echo ""

  if [ -n "$PREV_TAG" ] && [ "$PREV_TAG" != "$TAG" ]; then
    echo "Changes since \`$PREV_TAG\`:"
    echo ""
    git log "${PREV_TAG}..${TAG}" --no-merges \
      --pretty=format:"* %s ([%h](https://github.com/FarGroup/FarManager/commit/%H))"
  else
    echo "_First release in the builds/* series._"
  fi
} > "$OUTPUT_FILE"

echo "[generate_changelog.sh] Wrote release notes to $OUTPUT_FILE"
