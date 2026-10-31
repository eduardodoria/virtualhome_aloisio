#!/bin/bash
# publish_release.sh <dir> <zip name>: zips <dir> as a folder named after the app (Casa_Aloisio-linux.zip ->
# Casa_Aloisio/) and uploads it to the "builds" release of this repository, replacing the file of that name.
# A release asset, not a branch: the asset pack is over the 100 MB git on GitHub accepts in a file.
# Env: GH_TOKEN (the workflow's token, with contents: write).
set -euo pipefail
DIR=$1
ZIP=$2
TAG=builds
APP=${ZIP%-*}
export GH_REPO=$GITHUB_REPOSITORY
STAGE=$(mktemp -d)
cp -a "$DIR" "$STAGE/$APP"
if command -v zip >/dev/null; then
  (cd "$STAGE" && zip -qr "$ZIP" "$APP")
else
  (cd "$STAGE" && 7z a -tzip -bd "$ZIP" "$APP" > /dev/null)        # Windows runners have 7-Zip, not zip
fi
ls -la "$STAGE/$ZIP"
# the three desktop jobs may get here together: whoever comes first creates the release
gh release view "$TAG" > /dev/null 2>&1 || gh release create "$TAG" --target "$GITHUB_SHA" --title "Versões desktop" \
  --notes "Linux, Windows e macOS, refeitos pelo CI a cada publicação do projeto. Baixe o zip, extraia e rode Casa_Aloisio." || true
for try in 1 2 3; do
  gh release upload "$TAG" "$STAGE/$ZIP" --clobber && break
  sleep $((try * 10))
done
echo "$ZIP -> release $TAG"
