#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CLEAN_PATCHES=(
  app.html.patch
  constants.ts.patch
  favicon.svg.patch
  layout.svelte.patch
  static_favicon.svg.patch
)
MANUAL_PATCHES=(
  InputMenu.svelte.patch
  MessageInput.svelte.patch
  package.json.patch
)

echo ">>> Applying clean patches..."
for p in "${CLEAN_PATCHES[@]}"; do
  echo "  applying $p"
  git apply "custom-changes/patches/$p"
done

echo ">>> Copying static branding assets..."
cp -av custom-changes/backend/open_webui/static/. backend/open_webui/static/
cp -av custom-changes/static/static/. static/static/
cp -av custom-changes/static/favicon.png static/favicon.png

echo ">>> DONE with automated part."
echo ">>> The following patches MUST be applied by hand (vim):"
for p in "${MANUAL_PATCHES[@]}"; do echo "    custom-changes/patches/$p"; done
