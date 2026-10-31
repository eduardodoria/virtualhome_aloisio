#!/bin/bash
# join_pack.sh <export dir>: joins project/assets/resources.pak.000, .001 ... back into resources.pak
# (published in parts because git on GitHub refuses files over 100 MB)
set -euo pipefail
ASSETS=$1/project/assets
shopt -s nullglob
parts=("$ASSETS"/resources.pak.[0-9][0-9][0-9])
if [[ ${#parts[@]} -eq 0 ]]; then
  echo "no pack parts in $ASSETS"
  exit 0
fi
cat "${parts[@]}" > "$ASSETS/resources.pak"
rm -f "${parts[@]}"
ls -la "$ASSETS"
