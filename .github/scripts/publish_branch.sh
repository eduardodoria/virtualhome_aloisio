#!/bin/bash
# publish_branch.sh <dir> <branch>: pushes <dir> (the site) as a single-commit branch of this repository, so old
# builds do not pile up. Env: TOKEN (the workflow's token, with contents: write).
set -euo pipefail
DIR=$1
BRANCH=$2
git -C "$DIR" init -q -b "$BRANCH"
git -C "$DIR" add -A
git -C "$DIR" -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "Build from ${GITHUB_SHA:0:7}"
git -C "$DIR" push -q --force "https://x-access-token:${TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:refs/heads/${BRANCH}"
echo "$DIR -> $BRANCH"
