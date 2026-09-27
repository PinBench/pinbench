#!/usr/bin/env bash
#
# Runs the app with OpenTelemetry → Grafana Cloud enabled.
#
# Reads credentials from a gitignored .grafana.env (copy .grafana.env.example),
# builds the OTLP Basic-auth header, and injects the OTEL_* dart-defines so the
# secret never touches the command line or shell history.
#
# Usage:
#   tools/run_otel.sh [flutter run args...]
# Examples:
#   tools/run_otel.sh -d macos
#   tools/run_otel.sh -d windows --release
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.grafana.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found." >&2
  echo "       cp .grafana.env.example .grafana.env  # then fill in your values" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

: "${OTEL_GRAFANA_ENDPOINT:?set OTEL_GRAFANA_ENDPOINT in .grafana.env}"
: "${OTEL_GRAFANA_INSTANCE_ID:?set OTEL_GRAFANA_INSTANCE_ID in .grafana.env}"
: "${OTEL_GRAFANA_TOKEN:?set OTEL_GRAFANA_TOKEN in .grafana.env}"

# Basic auth = base64("<instanceId>:<token>"), single line.
auth="$(printf '%s:%s' "$OTEL_GRAFANA_INSTANCE_ID" "$OTEL_GRAFANA_TOKEN" | base64 | tr -d '\n')"

echo "OpenTelemetry → ${OTEL_GRAFANA_ENDPOINT} (instance ${OTEL_GRAFANA_INSTANCE_ID})"

exec flutter run \
  --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT="$OTEL_GRAFANA_ENDPOINT" \
  --dart-define=OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic ${auth}" \
  "$@"
