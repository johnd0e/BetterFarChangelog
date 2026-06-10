#!/bin/bash
# Generates Markdown release notes for a given tag.
# Called by process_tags.sh with:
#   $1 = TAG          e.g. "builds/6676"
#   $2 = OUTPUT_FILE  path where Markdown must be written
#
# Contract:
#   - Write valid non-empty Markdown to OUTPUT_FILE.
#   - Exit 0 on success, non-zero on any error (will stop the pipeline).
set -euo pipefail

TAG="$1"
OUTPUT_FILE="$2"

# Find the previous tag of the same format (for the commit range).
# 'git tag --sort=version:refname' lists in ascending order; we reverse it,
# find our tag and take the next line (which is the predecessor).
PREV_TAG=$(git tag --list 'builds/*' --sort=version:refname \
  | tac \
  | awk -v tag="$TAG" 'found{print; exit} $0==tag{found=1}')

{
  if [ -n "$PREV_TAG" ]; then
    echo "Changes since \`$PREV_TAG\`:"
    echo ""
    git log "${PREV_TAG}..${TAG}" --no-merges \
      --pretty=format:"* %s ([%h](https://github.com/FarGroup/FarManager/commit/%H))"
    echo ""
  else
    echo "_First tracked release._"
    echo ""
  fi
} > "$OUTPUT_FILE"

echo "[generate_changelog.sh] $TAG: wrote $(wc -l < "$OUTPUT_FILE") lines (prev: ${PREV_TAG:-none})"
