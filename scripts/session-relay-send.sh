#!/bin/bash
# session-relay-send.sh
# Append a directed cross-session relay signal to relay-signals.jsonl.
#
# This is the write side of the CCH internal relay (read side =
# session-relay-watch.sh). It writes to CCH's own signal store, so the content
# is subject to harness-mem redaction — but callers must still avoid putting
# secrets in <body>; companion integrations redact before calling this.
#
# Usage: session-relay-send.sh <from_session> <to_session> <body> [project_path]

set -euo pipefail

FROM="${1:?Usage: session-relay-send.sh <from_session> <to_session> <body> [project_path]}"
TO="${2:?Missing to_session}"
BODY="${3:?Missing body}"
PROJECT="${4:-$(pwd)}"

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required for relay send" >&2; exit 1; }

SESSIONS_DIR="${PROJECT}/.claude/sessions"
SIGNALS="${SESSIONS_DIR}/relay-signals.jsonl"
mkdir -p "$SESSIONS_DIR" 2>/dev/null || true

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FROM12="${FROM:0:12}"
TO12="${TO:0:12}"

# jq -cn builds the JSON object so body's quotes/newlines are escaped safely —
# never hand-format JSON with printf for attacker-or-user-controlled text.
jq -cn --arg ts "$TS" --arg from "$FROM12" --arg to "$TO12" --arg body "$BODY" \
  '{ts:$ts, from:$from, to:$to, body:$body}' >> "$SIGNALS"
