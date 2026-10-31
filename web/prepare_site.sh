#!/bin/bash
# Site for GitHub Pages from a web build: prepare_site.sh <build dir> <app name> <site dir>
# A Pages branch is a git branch, and git on GitHub refuses files over 100 MB. The data package
# (~150 MB) goes in 50 MB parts: <app>.data.000, .001 ... and <app>.data.parts with their names and
# total size. web/shell.html joins them back when <app>.data itself is not on the server.
set -euo pipefail
BUILD=$1
APP=$2
SITE=$3

rm -rf "$SITE"
mkdir -p "$SITE"
cp "$BUILD/index.html" "$BUILD/$APP.js" "$BUILD/$APP.wasm" "$SITE/"
[[ -f "$BUILD/favicon.png" ]] && cp "$BUILD/favicon.png" "$SITE/"
# no Jekyll: the files go out as they are
touch "$SITE/.nojekyll"

if [[ -f "$BUILD/$APP.data" ]]; then
  split -b 50M -d -a 3 "$BUILD/$APP.data" "$SITE/$APP.data."
  size=$(stat -c %s "$BUILD/$APP.data")
  parts=$(cd "$SITE" && ls "$APP".data.[0-9][0-9][0-9] | sed 's/.*/"&"/' | paste -sd, -)
  printf '{"size": %s, "parts": [%s]}\n' "$size" "$parts" > "$SITE/$APP.data.parts"
fi

ls -la "$SITE"
