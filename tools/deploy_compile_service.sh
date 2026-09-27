#!/usr/bin/env bash
# Deploy the arduino-cli compile service to the production VM.
#
# This exists because the repo and the VM silently diverged: production was
# found running a 4.6 KB server.js while the repo had ~27 KB, with no
# node_modules at all and /metrics returning 404 for weeks. Hand-copying via
# scp is how that happened. Use this instead.
#
# What it does, in order:
#   1. Verifies locally  — node --check + npm test (never ship a red build)
#   2. Uploads           — server.js + package.json to the VM's /tmp
#   3. Backs up          — the live server.js and package.json
#   4. Installs deps     — npm ci/install, because server.js needs prom-client
#   5. Load-checks       — requires the new file *in place* before restarting
#   6. Restarts          — systemctl restart
#   7. VERIFIES          — health, auth, and a real end-to-end compile
#   8. Rolls back        — automatically, if any verification step fails
#
# Step 7 is the point of the script. `systemctl is-active` reports "active" for
# a service that cannot compile anything — e.g. when ProtectHome=yes hides
# arduino-cli's toolchain in ~/.arduino15. Only a real compile proves a deploy
# worked.
#
# This script does NOT manage the systemd unit. The unit encodes host-specific
# hardening (paths, ReadWritePaths, origins) and changing it is a deliberate,
# reviewed act, made on the VM itself.
#
# Configuration (env vars, all optional except where noted):
# Read from tools/deploy.env (git-ignored; template: tools/deploy.env.example),
# or from the environment, which wins.
#   COMPILE_SSH_HOST   VM host          (required)
#   COMPILE_SSH_USER   VM user          (default: ubuntu)
#   COMPILE_SSH_KEY    private key      (required)
#   COMPILE_REMOTE_DIR install dir      (default: /opt/compile)
#   COMPILE_SERVICE    systemd unit     (default: compile)
#   COMPILE_API_URL    public base URL  (required)
#   COMPILE_ORIGIN     Origin header used for the verification compile
#                      (default: https://pinbench.web.app)
#
# Usage:
#   tools/deploy_compile_service.sh
#   tools/deploy_compile_service.sh --dry-run     # verify + show plan, change nothing
#   tools/deploy_compile_service.sh --skip-tests  # emergencies only
#   COMPILE_SSH_HOST=1.2.3.4 tools/deploy_compile_service.sh
#
# NOTE: if the VM's public IP changes, update COMPILE_SSH_HOST and
# COMPILE_API_URL in tools/deploy.env.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/compile_service"

# shellcheck source=/dev/null
[ -f "$ROOT/tools/deploy.env" ] && . "$ROOT/tools/deploy.env"

SSH_HOST="${COMPILE_SSH_HOST:?set COMPILE_SSH_HOST in tools/deploy.env (see deploy.env.example)}"
SSH_USER="${COMPILE_SSH_USER:-ubuntu}"
SSH_KEY="${COMPILE_SSH_KEY:?set COMPILE_SSH_KEY in tools/deploy.env (see deploy.env.example)}"
REMOTE_DIR="${COMPILE_REMOTE_DIR:-/opt/compile}"
SERVICE="${COMPILE_SERVICE:-compile}"
ORIGIN="${COMPILE_ORIGIN:-https://pinbench.web.app}"
PUBLIC_URL="${COMPILE_API_URL:?set COMPILE_API_URL in tools/deploy.env (see deploy.env.example)}"

DRY_RUN=0
SKIP_TESTS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    -h|--help)    sed -n '2,46p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument '$arg' (try --help)" >&2; exit 2 ;;
  esac
done

SSH=(ssh -i "$SSH_KEY" -o ConnectTimeout=20 -o BatchMode=yes "$SSH_USER@$SSH_HOST")
SCP=(scp -i "$SSH_KEY" -o ConnectTimeout=20 -o BatchMode=yes)

say()  { printf '==> %s\n' "$*"; }
warn() { printf '==> WARNING: %s\n' "$*" >&2; }
die()  { printf '==> ERROR: %s\n' "$*" >&2; exit 1; }

# ── 1. Local preflight ────────────────────────────────────────────────────────
say "Verifying locally…"

[[ -f "$SRC/server.js" ]]    || die "$SRC/server.js not found"
[[ -f "$SRC/package.json" ]] || die "$SRC/package.json not found"
command -v node >/dev/null   || die "node not found on PATH"
[[ -f "$SSH_KEY" ]]          || die "SSH key not found: $SSH_KEY"

node --check "$SRC/server.js" || die "server.js has a syntax error — not deploying"

if [[ "$SKIP_TESTS" -eq 0 ]]; then
  ( cd "$SRC" && npm test ) || die "tests failed — not deploying (override with --skip-tests)"
else
  warn "--skip-tests: shipping without running the test suite"
fi

# Warn on uncommitted service changes. Not fatal — hotfixes are legitimate —
# but a deploy that does not correspond to a commit is how drift starts.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if ! git -C "$ROOT" diff --quiet -- compile_service 2>/dev/null ||
     ! git -C "$ROOT" diff --cached --quiet -- compile_service 2>/dev/null; then
    warn "compile_service/ has uncommitted changes — deploying working-tree state"
  fi
fi

say "Local checks passed."

# ── 2. Connectivity + remote preflight ────────────────────────────────────────
say "Connecting to ${SSH_USER}@${SSH_HOST}…"
"${SSH[@]}" true || die "cannot reach $SSH_HOST over SSH (ephemeral IP changed?)"

REMOTE_INFO="$("${SSH[@]}" "
  printf 'node=%s\n' \"\$(node --version 2>/dev/null || echo MISSING)\"
  printf 'npm=%s\n'  \"\$(npm --version 2>/dev/null || echo MISSING)\"
  printf 'cli=%s\n'  \"\$(command -v arduino-cli || echo MISSING)\"
  printf 'dir=%s\n'  \"\$([ -d '$REMOTE_DIR' ] && echo present || echo MISSING)\"
  printf 'svc=%s\n'  \"\$(systemctl is-enabled '$SERVICE' 2>/dev/null || echo MISSING)\"
  printf 'live=%s\n' \"\$(stat -c%s '$REMOTE_DIR/server.js' 2>/dev/null || echo 0)\"
")"
echo "$REMOTE_INFO" | sed 's/^/    /'

grep -q 'node=MISSING' <<<"$REMOTE_INFO" && die "node not installed on the VM"
grep -q 'npm=MISSING'  <<<"$REMOTE_INFO" && die "npm not installed on the VM"
grep -q 'cli=MISSING'  <<<"$REMOTE_INFO" && die "arduino-cli not on the VM's PATH"
grep -q 'dir=MISSING'  <<<"$REMOTE_INFO" && die "$REMOTE_DIR does not exist on the VM"
grep -q 'svc=MISSING'  <<<"$REMOTE_INFO" && die "systemd unit '$SERVICE' not found"

LOCAL_SIZE="$(wc -c < "$SRC/server.js" | tr -d ' ')"
LIVE_SIZE="$(sed -n 's/^live=//p' <<<"$REMOTE_INFO")"
say "server.js: local ${LOCAL_SIZE}B → remote ${LIVE_SIZE}B"

if [[ "$DRY_RUN" -eq 1 ]]; then
  say "--dry-run: verified and connected. Nothing was changed."
  exit 0
fi

# ── 3-6. Upload, back up, install, load-check, restart ────────────────────────
say "Uploading…"
"${SCP[@]}" "$SRC/server.js" "$SRC/package.json" "$SSH_USER@$SSH_HOST:/tmp/" \
  || die "upload failed"

say "Installing and restarting…"
"${SSH[@]}" "bash -s" <<REMOTE || die "remote deploy step failed — service left on the previous version"
set -euo pipefail
cd '$REMOTE_DIR'

# Back up whatever is live so rollback is one copy.
cp -f server.js server.js.bak 2>/dev/null || true
cp -f package.json package.json.bak 2>/dev/null || true

cp /tmp/package.json package.json

# server.js requires prom-client; a missing dep is a crash loop under
# Restart=always, not a clean failure. Install before swapping the file.
if [ -f package-lock.json ]; then
  npm ci --omit=dev --no-audit --no-fund
else
  npm install --omit=dev --no-audit --no-fund
fi

cp /tmp/server.js server.js

# Prove it loads *from its install path* — module resolution is relative to the
# file, so checking it in /tmp would look for /tmp/node_modules and mislead.
# require() does not start a listener (server.js only listens as main).
node -e "require('$REMOTE_DIR/server.js')" >/dev/null

sudo systemctl restart '$SERVICE'
REMOTE

# ── 7. Verify — the part that actually matters ────────────────────────────────
say "Verifying deployment…"
sleep 3

rollback() {
  warn "Verification failed: $1"
  warn "Rolling back to the previous server.js…"
  "${SSH[@]}" "
    set -e
    cd '$REMOTE_DIR'
    [ -f server.js.bak ] && cp -f server.js.bak server.js
    [ -f package.json.bak ] && cp -f package.json.bak package.json
    sudo systemctl restart '$SERVICE'
  " && warn "Rolled back. Service restarted on the previous version." \
    || warn "ROLLBACK FAILED — the service may be down. SSH in and investigate."
  exit 1
}

STATE="$("${SSH[@]}" "systemctl is-active '$SERVICE' || true")"
[[ "$STATE" == "active" ]] || rollback "service is '$STATE', not active"
say "  service active"

# A startup warning box means a security setting did not take effect.
if "${SSH[@]}" "journalctl -u '$SERVICE' -n 30 --no-pager -o cat" \
     | grep -q 'permissive configuration'; then
  warn "  service started with a PERMISSIVE configuration — check the unit's"
  warn "  Environment= lines (ALLOWED_ORIGINS / COMPILE_API_TOKEN)."
fi

HEALTH="$("${SSH[@]}" "curl -sS --max-time 10 localhost:8080/health || true")"
grep -q '"ok":true' <<<"$HEALTH" || rollback "/health did not return ok:true"
say "  /health ok"

# Auth must reject an unauthenticated compile when a token is configured.
TOKEN="$("${SSH[@]}" "sudo grep -hoP 'COMPILE_API_TOKEN=\K.*' /etc/compile/env 2>/dev/null || true")"
if [[ -n "$TOKEN" ]]; then
  CODE="$("${SSH[@]}" "curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    -X POST -H 'Content-Type: application/json' -d '{}' localhost:8080/compile || true")"
  [[ "$CODE" == "401" ]] || rollback "unauthenticated /compile returned $CODE, expected 401"
  say "  unauthenticated /compile → 401"
  AUTH_HEADER=(-H "Authorization: Bearer $TOKEN")
else
  warn "  no COMPILE_API_TOKEN configured — /compile is unauthenticated"
  AUTH_HEADER=()
fi

# The real test: does it still compile? This is what catches a sandbox that
# hides arduino-cli's toolchain, a missing core, or a broken temp dir — none of
# which affect `is-active` or /health.
say "  running end-to-end compile…"
SKETCH='void setup(){pinMode(13,OUTPUT);}\nvoid loop(){digitalWrite(13,HIGH);delay(500);digitalWrite(13,LOW);delay(500);}'
RESP="$(curl -sS --max-time 90 -X POST "$PUBLIC_URL/compile" \
  "${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"}" \
  -H 'Content-Type: application/json' \
  -H "Origin: $ORIGIN" \
  -d "{\"sketch\":\"blink\",\"fqbn\":\"arduino:avr:uno\",\"files\":{\"blink.ino\":\"$SKETCH\"}}" \
  || echo '{"error":"request_failed"}')"

grep -q '"hex"' <<<"$RESP" \
  || rollback "end-to-end compile produced no hex: $(head -c 300 <<<"$RESP")"

DURATION="$(grep -o '"durationMs":[0-9]*' <<<"$RESP" | head -1 | cut -d: -f2)"
say "  end-to-end compile OK (${DURATION:-?} ms via $PUBLIC_URL)"

say "Deployed successfully."
echo
echo "    Public URL : $PUBLIC_URL"
echo "    Rollback   : ssh $SSH_USER@$SSH_HOST 'cd $REMOTE_DIR && cp server.js.bak server.js && sudo systemctl restart $SERVICE'"
echo
echo "    If server.js changed how the web app talks to it, redeploy the app:"
echo "      COMPILE_API_TOKEN=… tools/deploy_web.sh"
