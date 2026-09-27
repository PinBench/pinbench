#!/usr/bin/env bash
# Assemble the whole public site into build/web — the directory firebase.json
# serves.
#
# The site is two things with very different weights:
#
#   /            site/index.html    a ~30 KB static landing page
#   /download    site/download.html the release/checkout page
#   /app/**      the Flutter bundle ~48 MB of WASM, CanvasKit and fonts
#
# Keeping the landing page static is the entire point of the split. Someone
# arriving from Hacker News or a search result gets readable content in one
# round trip instead of waiting on a multi-megabyte engine download to find
# out what the thing is. The app is one click away at /app/ for anyone who
# actually wants to use it.
#
# So the Flutter build goes to a SUBDIRECTORY (--output=build/web/app) and is
# told about it (--base-href=/app/). Both are required and they must agree:
# --output alone puts the files in app/ while index.html still asks for
# /main.dart.wasm, and --base-href alone rewrites the URLs to point at a
# directory with nothing in it. Either way the app loads a blank page.
#
# Everything in site/ is then copied OVER that, at the root. site/ is copied
# last so a file there always wins; nothing in it currently collides with a
# Flutter output, and if one ever does, the hand-written page is the one to
# keep.
#
# Used by both tools/deploy_web.sh and the build-web job in ci.yml, so the two
# cannot drift into deploying different layouts.
#
# Usage:
#   tools/build_site.sh [extra flutter build args…]
#
#   tools/build_site.sh
#   tools/build_site.sh --dart-define=COMPILE_API_URL=https://…
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="build/web"

# A stale app/ from an earlier build would otherwise leave orphaned assets
# behind — `flutter build` writes into the directory, it does not clear it.
rm -rf "${OUT:?}/app"

echo "==> Building Flutter web (WASM) into ${OUT}/app …"
flutter build web \
  --wasm \
  --pwa-strategy=none \
  --base-href=/app/ \
  --output="${OUT}/app" \
  "$@"

echo "==> Copying the static site over it…"
# `site/.` rather than `site/*` so dotfiles come too.
cp -R site/. "${OUT}/"

# Fail loudly here rather than deploying a site whose front door 404s. Both
# halves have been silently missing during development — once from a Flutter
# build that failed after the copy, once from a typo in the copy itself.
test -f "${OUT}/index.html"     || { echo "==> Error: no ${OUT}/index.html (landing page missing)" >&2; exit 1; }
test -f "${OUT}/app/index.html" || { echo "==> Error: no ${OUT}/app/index.html (Flutter build missing)" >&2; exit 1; }

echo "==> Site assembled in ${OUT}/"
