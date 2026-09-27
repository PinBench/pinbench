#!/usr/bin/env bash
#
# Creates the Appwrite schema that AppwriteProjectRepository expects.
#
# Appwrite has no schema-on-write, so every table, column and index below must
# exist before the app can talk to it. Doing that by hand through the console is
# forty-odd form submissions with several non-obvious traps (see the size and
# index-length notes below), so it lives here instead: reproducible, reviewable,
# and re-runnable against a fresh project.
#
# Idempotent — existing resources are reported and skipped, so this is safe to
# re-run after a partial failure.
#
# Usage — either authentication works:
#
#   appwrite login                     # interactive, session kept in ~/.appwrite
#   ./tools/appwrite_schema.sh
#
#   # or, for unattended runs:
#   export APPWRITE_API_KEY=...        # console -> Overview -> API keys
#   ./tools/appwrite_schema.sh
#
# A login session is simpler for a one-off run by the project owner. Prefer a
# key when this runs unattended: it is scoped to `databases.read` +
# `databases.write` and can be revoked on its own, whereas a session carries
# whatever the account can do. Either way it is a *server* credential — never
# commit it, never ship it in the app.
#

set -euo pipefail

ENDPOINT="${APPWRITE_ENDPOINT:-https://fra.cloud.appwrite.io/v1}"
PROJECT_ID="${APPWRITE_PROJECT_ID:-6a6f515f002ba74d8af8}"
DB="${APPWRITE_DATABASE_ID:-playground}"

command -v appwrite >/dev/null || { echo "appwrite CLI not found: npm i -g appwrite-cli" >&2; exit 1; }

export APPWRITE_ENDPOINT="$ENDPOINT"
export APPWRITE_PROJECT_ID="$PROJECT_ID"

# Fail here rather than partway through, where a half-built schema would need
# untangling. An API key takes precedence when both are present.
if [[ -z "${APPWRITE_API_KEY:-}" ]] && ! appwrite whoami >/dev/null 2>&1; then
  echo "Not authenticated. Either:" >&2
  echo "  appwrite login" >&2
  echo "or create a key at console -> Overview -> API keys with" >&2
  echo "databases.read + databases.write, then: export APPWRITE_API_KEY=..." >&2
  exit 1
fi

# Every call is wrapped: Appwrite returns 409 for an existing resource, which is
# success as far as this script is concerned. Any other failure is real and
# stops the run, so a typo'd column doesn't leave a half-built schema that looks
# finished.
run() {
  local label="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    echo "  created  $label"
  elif grep -qiE "already exists|409" <<<"$out"; then
    echo "  exists   $label"
  else
    echo "  FAILED   $label" >&2
    echo "$out" >&2
    exit 1
  fi
}

# Create only when absent, rather than creating and forgiving the failure.
#
# Appwrite checks the plan quota before the duplicate check, so re-creating an
# existing database on the free plan (limit: one) reports "maximum number of
# databases reached" rather than a 409 — indistinguishable, by its error alone,
# from genuinely being out of quota. Asking first sidesteps having to classify
# errors at all.
ensure() {
  local label="$1" get_cmd="$2"; shift 2
  if eval "$get_cmd" >/dev/null 2>&1; then
    echo "  exists   $label"
  else
    run "$label" "$@"
  fi
}

# col <create-*-column> <table> <key> [flags...]
col() { run "$2.$3" appwrite tablesdb "$1" --database-id "$DB" --table-id "$2" --key "$3" "${@:4}"; }

# Columns provision asynchronously. An index created against a column still in
# `processing` fails, so wait for the whole table to settle first.
wait_for_columns() {
  local table="$1" tries=0
  printf '  waiting for %s columns' "$table"
  until [[ -z "$(appwrite tablesdb list-columns --database-id "$DB" --table-id "$table" --raw 2>/dev/null \
        | grep -oE '"status":"(processing|failed)"' || true)" ]]; do
    (( ++tries > 60 )) && { echo " timed out" >&2; exit 1; }
    printf '.'; sleep 1
  done
  echo " ready"
}

echo "==> database"
ensure "database $DB" "appwrite tablesdb get --database-id '$DB'" \
  appwrite tablesdb create --database-id "$DB" --name "playground"

# --- projects -------------------------------------------------------------
# Row security on, plus exactly one table-wide permission: create.
#
# Row permissions govern rows that already exist, so with no table permissions
# at all nobody can insert anything — every save fails with "No permissions
# provided for action 'create' (401)". Creating is necessarily a table-level
# operation: there is no row yet to carry a permission.
#
# Only create. A table-level read would grant read on *every* row regardless of
# who owns it, because a user needs one of row or table-level permissions — the
# two are OR'd, not AND'd. Read, update and delete stay with the per-row
# permissions the repository writes at save time.
echo "==> projects"
ensure "table projects" "appwrite tablesdb get-table --database-id '$DB' --table-id projects" \
  appwrite tablesdb create-table \
  --database-id "$DB" --table-id projects --name projects --row-security true \
  --permissions 'create("users")'

col create-varchar-column projects name --size 255 --required true
col create-varchar-column projects ownerId --size 64 --required true

# Enum rather than a string so a typo'd value fails at write time instead of
# being stored and silently read back as `private`. Appwrite makes required and
# default mutually exclusive; the default wins here because it fails closed.
col create-enum-column projects visibility \
  --elements private unlisted public --required false --xdefault private

# JSON blobs: Appwrite has no map type and these are only ever read whole and
# rewritten, never queried by key.
#
# `text`, not a sized varchar. InnoDB caps a row at 65,535 bytes and counts
# varchar contents against it, so three varchar(8192) columns are ~98KB of
# declared row on their own and the third one fails with "maximum number or
# size of columns has been reached". A text column stores off-page and leaves
# only a pointer in the row. Its 16,383-character ceiling is far past any
# plausible collaborator list.
col create-text-column projects collaborators --required false
col create-text-column projects pendingInvites --required false
col create-text-column projects collaboratorEmails --required false

# Deliberately not the built-in $createdAt/$updatedAt: those are server-stamped
# and read-only, so a migrated project could never keep its real creation date,
# and $updatedAt would move on permission rewrites that aren't edits.
col create-datetime-column projects createdAt --required true
col create-datetime-column projects updatedAt --required true

# --- files ----------------------------------------------------------------
echo "==> files"
ensure "table files" "appwrite tablesdb get-table --database-id '$DB' --table-id files" \
  appwrite tablesdb create-table \
  --database-id "$DB" --table-id files --name files --row-security true \
  --permissions 'create("users")'

col create-varchar-column files projectId --size 64 --required true
col create-varchar-column files path --size 512 --required true
# mediumtext, not varchar: varchar caps at 16381 characters, which a large
# circuit plus its sketch can exceed.
col create-mediumtext-column files content --required false
col create-datetime-column files updatedAt --required true
col create-varchar-column files updatedBy --size 64 --required true

wait_for_columns files

# No index prefix lengths needed, because the columns above are sized honestly.
# Creating these through the console fails with "index length is longer than the
# maximum: 767" — not because the index is too wide, but because the console
# creates every text column at its 16,383-character default, which is ~65KB of
# index for a field holding a 20-character id.
#
# Both are `key`. A unique index on projectId_path would express the
# one-row-per-file invariant more directly, and is worth revisiting; it is left
# as `key` because saveFile's query-then-upsert already holds the invariant and
# a unique constraint turns a lost race into a failed save.
run "index files.projectId" appwrite tablesdb create-index \
  --database-id "$DB" --table-id files --key projectId \
  --type key --columns projectId --orders ASC

run "index files.projectId_path" appwrite tablesdb create-index \
  --database-id "$DB" --table-id files --key projectId_path \
  --type key --columns projectId path --orders ASC ASC

# --- recents --------------------------------------------------------------
# Row id is {userId}_{projectId}, so re-opening a project overwrites its entry
# rather than accumulating one per visit.
echo "==> recents"
ensure "table recents" "appwrite tablesdb get-table --database-id '$DB' --table-id recents" \
  appwrite tablesdb create-table \
  --database-id "$DB" --table-id recents --name recents --row-security true \
  --permissions 'create("users")'

col create-varchar-column recents userId --size 64 --required true
col create-varchar-column recents projectId --size 64 --required true
col create-varchar-column recents name --size 255 --required true
col create-datetime-column recents lastOpenedAt --required true

wait_for_columns recents

run "index recents.userId" appwrite tablesdb create-index \
  --database-id "$DB" --table-id recents --key userId \
  --type key --columns userId --orders ASC

echo
echo "Schema ready. Verify: appwrite tablesdb list-tables --database-id $DB"
