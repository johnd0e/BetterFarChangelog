#!/bin/bash
# Placeholder for changelog generation logic.
# Called by process_tags.sh with:
#   $1 = TAG        e.g. "builds/6676"
#   $2 = OUTPUT_FILE  path where Markdown must be written
#
# Contract:
#   - Write valid Markdown to OUTPUT_FILE.
#   - Exit 0 on success, non-zero on any error (will stop the pipeline).
set -euo pipefail

TAG="$1"
OUTPUT_FILE="$2"

# Find the chronologically previous tag of the same format.
# ls-remote sorts descending (-v:refname), so the second result is the predecessor.
PREV_TAG=$(git ls-remote --tags --sort=-v:refname upstream "refs/tags/builds/*" \
  | awk -F'refs/tags/' '{print $2}' \
  | grep -v '\^{}' \
  | awk -v tag="$TAG" 'found{print; exit} $0==tag{found=1}')

{
  echo "## $TAG"
  echo ""

  if [ -n "$PREV_TAG" ] && [ "$PREV_TAG" != "$TAG" ]; then
    echo "Changes since \`$PREV_TAG\`:"
    echo ""
    git log "refs/tags/${PREV_TAG}..refs/tags/${TAG}" --no-merges \
      --pretty=format:"* %s ([%h](https://github.com/FarGroup/FarManager/commit/%H))"
  else
    echo "_First tracked release._"
  fi
  echo ""
} > "$OUTPUT_FILE"

echo "[generate_changelog.sh] Wrote $(wc -l < "$OUTPUT_FILE") lines to $OUTPUT_FILE"
