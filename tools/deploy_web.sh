#!/usr/bin/env bash
# Build the Flutter web bundle and deploy it to Firebase Hosting.
#
# Prerequisites (one-time):
#   1. npm install -g firebase-tools   # install the Firebase CLI
#   2. firebase login                  # authenticate (opens a browser)
#   3. firebase projects:create <id>   # or use an existing project
#      firebase use <project-id>       # writes .firebaserc
#
# Remote compile service (lets the web app compile edited sketches):
#   COMPILE_API_URL is the HTTPS base URL of your arduino-cli service
#   (see compile_service/README.md). Set it in tools/deploy.env (git-ignored;
#   template: tools/deploy.env.example) or in the environment, which wins. Set
#   it to "" to build with bundled precompiled templates only. Unset, the build
#   stops rather than guess.
#
# Optional:
#   COMPILE_API_TOKEN  — bearer token, must match the service's COMPILE_API_TOKEN.
#                        Public by nature (it ships in the JS bundle) — see
#                        compile_service/README.md § Security.
#
# Usage:
#   tools/deploy_web.sh
#   COMPILE_API_URL=https://compile.example.com tools/deploy_web.sh
#   COMPILE_API_TOKEN=… tools/deploy_web.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# ── Validate prerequisites ────────────────────────────────────────────────────
if ! command -v firebase &>/dev/null; then
  echo "==> Error: firebase CLI not found. Install it with: npm install -g firebase-tools"
  exit 1
fi

if ! command -v flutter &>/dev/null; then
  echo "==> Error: flutter not found on PATH."
  exit 1
fi

# ── Dart defines ──────────────────────────────────────────────────────────────
# shellcheck source=/dev/null
[ -f tools/deploy.env ] && . tools/deploy.env

# Entirely unset is a mistake; an explicit COMPILE_API_URL="" still means
# "precompiled templates only".
if [ -z "${COMPILE_API_URL+set}" ]; then
  echo "==> COMPILE_API_URL is not set. Put it in tools/deploy.env (see" >&2
  echo "    tools/deploy.env.example), or pass COMPILE_API_URL=\"\" to build with" >&2
  echo "    the bundled precompiled templates only." >&2
  exit 1
fi

DART_DEFINES=()
if [ -n "${COMPILE_API_URL}" ]; then
  DART_DEFINES+=(--dart-define=COMPILE_API_URL="${COMPILE_API_URL}")
  echo "==> Compile service: ${COMPILE_API_URL}"

  # Shared bearer token, if the service is configured with one. This is NOT a
  # secret — it ends up in the JavaScript bundle and anyone can read it from
  # devtools. It deters casual scripted abuse of the endpoint; the service's
  # rate limiting and concurrency caps are the real protection.
  if [ "${COMPILE_API_TOKEN:-}" = "none" ]; then
    echo "==> Compile token: explicitly disabled"
  elif [ -n "${COMPILE_API_TOKEN:-}" ]; then
    DART_DEFINES+=(--dart-define=COMPILE_API_TOKEN="${COMPILE_API_TOKEN}")
    echo "==> Compile token: set (${#COMPILE_API_TOKEN} chars)"
  else
    # Refuse rather than warn. A token-less build looks completely healthy —
    # it deploys, loads, and runs — and only fails at the moment a user hits
    # Compile, with an error about self-hosting that means nothing to them.
    # A warning scrolls past in build output; this does not.
    echo "==> COMPILE_API_TOKEN is unset." >&2
    echo "    ${COMPILE_API_URL} requires a bearer token, so a build without one" >&2
    echo "    deploys fine and then fails on every compile with 'unauthorized'." >&2
    echo >&2
    echo "    Read it from the service and re-run in one step, e.g.:" >&2
    echo "      COMPILE_API_TOKEN=\$(ssh -i \"\$COMPILE_SSH_KEY\" \"\$COMPILE_SSH_USER@\$COMPILE_SSH_HOST\" \\" >&2
    echo "        '<print the COMPILE_API_TOKEN the service runs with>') tools/deploy_web.sh" >&2
    echo >&2
    echo "    If your service genuinely runs without auth:" >&2
    echo "      COMPILE_API_TOKEN=none tools/deploy_web.sh" >&2
    exit 1
  fi
else
  echo "==> COMPILE_API_URL empty — building with precompiled templates only."
fi

# CanvasKit memory limit (256 MiB surface cache cap, good for most devices).
DART_DEFINES+=(--dart-define=FLUTTER_WEB_CANVASKIT_MAX_SURFACE_SIZE=2048)

# ── Build ──────────────────────────────────────────────────────────────────────
# The landing page at / and the app at /app/ are assembled by build_site.sh,
# which CI's build-web job runs too — so a local deploy and a CI deploy can
# never publish different layouts. The --wasm, --pwa-strategy=none,
# --base-href and --output flags all live in there.
if ! tools/build_site.sh "${DART_DEFINES[@]+"${DART_DEFINES[@]}"}"; then
  echo "==> Site build failed — aborting deployment."
  # If it failed on "Couldn't resolve the package 'firebase_..._web'", the
  # generated web_plugin_registrant.dart is stale: removing a dependency does
  # not invalidate it, so it still imports the plugin that is gone. Fix with
  #   rm -rf .dart_tool/flutter_build
  # rather than a full `flutter clean`, which also discards the pod cache.
  exit 1
fi

# ── Deploy ─────────────────────────────────────────────────────────────────────
echo "==> Deploying to Firebase Hosting…"
if ! firebase deploy --only hosting; then
  echo "==> Firebase deploy failed — build artifacts are still in build/web."
  exit 1
fi

echo "==> Done."
echo "    Landing page: the Hosting URL printed above"
echo "    The app:      that URL + /app/"
