#!/bin/bash
# tests/test-harness-command-center.sh
# Phase 65.6.1 - harness-command-center skill + command-center-snapshot.v1 の機械検証
#
# 検証ケース (Plans.md §65.6.1 DoD a-f):
#   (a) skills/harness-command-center/SKILL.md 存在 + 必須 frontmatter (i18n: description / -en / -ja)
#   (b) command-center-snapshot.v1 schema 存在 + JSON 構文 valid
#   (c) command-center-compile.sh が exit 0 で snapshot を出力
#   (d) snapshot に projects[] / activities[] / drift_alerts[] が含まれる
#   (e) command-center.html.template から HTML をレンダリングしても {{...}} が残らない
#   (f) HTML に literal Japanese ("プロジェクト" "判断待ち" 等) が含まれる (i18n)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SKILL_MD="$ROOT_DIR/skills/harness-command-center/SKILL.md"
SCHEMA="$ROOT_DIR/skills/harness-command-center/schemas/command-center-snapshot.v1.schema.json"
COMPILE_SCRIPT="$ROOT_DIR/scripts/command-center-compile.sh"
RENDER_SCRIPT="$ROOT_DIR/scripts/render-html.sh"
TEMPLATE="$ROOT_DIR/templates/html/command-center.html.template"

PASS=0
FAIL=0
FAIL_MESSAGES=()

pass() { PASS=$((PASS + 1)); echo "✓ $1"; }
fail() { FAIL=$((FAIL + 1)); FAIL_MESSAGES+=("$1"); echo "✗ $1" >&2; }

# ============================================================
# (a) SKILL.md 存在 + frontmatter (i18n compliance)
# ============================================================

if [[ -f "$SKILL_MD" ]]; then
  pass "(a) skills/harness-command-center/SKILL.md exists"
else
  fail "(a) SKILL.md missing"
  echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi

if grep -q "^name: harness-command-center" "$SKILL_MD"; then
  pass "(a) SKILL.md frontmatter: name = harness-command-center"
else
  fail "(a) SKILL.md frontmatter name missing"
fi

if grep -q "^description:" "$SKILL_MD"; then
  pass "(a) SKILL.md has description"
else
  fail "(a) SKILL.md missing description"
fi

if grep -q "^description-en:" "$SKILL_MD"; then
  pass "(a) SKILL.md has description-en (i18n gate)"
else
  fail "(a) SKILL.md missing description-en"
fi

if grep -q "^description-ja:" "$SKILL_MD"; then
  pass "(a) SKILL.md has description-ja (i18n gate)"
else
  fail "(a) SKILL.md missing description-ja"
fi

# allowed-tools must include the 3 we use
if grep -q '^allowed-tools.*Bash' "$SKILL_MD"; then
  pass "(a) SKILL.md allowed-tools includes Bash"
else
  fail "(a) SKILL.md allowed-tools missing Bash"
fi

# ============================================================
# (b) Schema valid
# ============================================================

if [[ -f "$SCHEMA" ]]; then
  pass "(b) schema file exists"
else
  fail "(b) schema file missing: $SCHEMA"
fi

if jq empty "$SCHEMA" 2>/dev/null; then
  pass "(b) schema is valid JSON"
else
  fail "(b) schema is not valid JSON"
fi

if jq -e '.title == "command-center-snapshot.v1"' "$SCHEMA" >/dev/null; then
  pass "(b) schema title = command-center-snapshot.v1"
else
  fail "(b) schema title mismatch"
fi

# Required fields includes the critical ones
if jq -e '.required | index("projects") and index("activities") and index("drift_alerts")' "$SCHEMA" >/dev/null; then
  pass "(b) schema requires projects + activities + drift_alerts"
else
  fail "(b) schema missing required: projects / activities / drift_alerts"
fi

# ============================================================
# (c) compile.sh works
# ============================================================

if [[ -f "$COMPILE_SCRIPT" && -x "$COMPILE_SCRIPT" ]]; then
  pass "(c) command-center-compile.sh exists and is executable"
else
  fail "(c) command-center-compile.sh missing or not executable"
  echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi

TMPDIR_TEST="$(mktemp -d /tmp/cc-test-XXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

if bash "$COMPILE_SCRIPT" --project test-project --plans Plans.md --out "$TMPDIR_TEST/snap.json" 2>"$TMPDIR_TEST/err.log"; then
  pass "(c) compile.sh exit 0"
else
  fail "(c) compile.sh exit non-zero — stderr: $(cat "$TMPDIR_TEST/err.log")"
fi

# ============================================================
# (d) snapshot contains expected arrays
# ============================================================

if [[ -f "$TMPDIR_TEST/snap.json" ]] && jq empty "$TMPDIR_TEST/snap.json" 2>/dev/null; then
  pass "(d) snapshot is valid JSON"
else
  fail "(d) snapshot is not valid JSON"
fi

if jq -e '.schema == "command-center-snapshot.v1"' "$TMPDIR_TEST/snap.json" >/dev/null; then
  pass "(d) snapshot schema field correct"
else
  fail "(d) snapshot schema field wrong"
fi

if jq -e '.projects | type == "array" and length > 0' "$TMPDIR_TEST/snap.json" >/dev/null; then
  pass "(d) snapshot has non-empty projects[]"
else
  fail "(d) snapshot projects[] empty or wrong type"
fi

if jq -e '.activities | type == "array"' "$TMPDIR_TEST/snap.json" >/dev/null; then
  pass "(d) snapshot has activities[] (array)"
else
  fail "(d) snapshot activities not array"
fi

if jq -e '.drift_alerts | type == "array" and length == 5' "$TMPDIR_TEST/snap.json" >/dev/null; then
  pass "(d) snapshot has drift_alerts[] with 5 entries"
else
  fail "(d) snapshot drift_alerts wrong length"
fi

# Active project name correct
if jq -e '.active_project == "test-project"' "$TMPDIR_TEST/snap.json" >/dev/null; then
  pass "(d) snapshot active_project echoed back from --project flag"
else
  fail "(d) snapshot active_project mismatch"
fi

# ============================================================
# (e) Render HTML — no {{...}} left
# ============================================================

if [[ -f "$TEMPLATE" ]]; then
  pass "(e) template file exists"
else
  fail "(e) template missing: $TEMPLATE"
fi

if bash "$RENDER_SCRIPT" --template command-center --data "$TMPDIR_TEST/snap.json" --out "$TMPDIR_TEST/cc.html" 2>"$TMPDIR_TEST/render-err.log"; then
  pass "(e) render-html.sh exit 0"
else
  fail "(e) render-html.sh failed — stderr: $(cat "$TMPDIR_TEST/render-err.log")"
fi

if [[ -f "$TMPDIR_TEST/cc.html" ]]; then
  LEFTOVER="$(grep -c '{{' "$TMPDIR_TEST/cc.html" || true)"
  [[ "$LEFTOVER" =~ ^[0-9]+$ ]] || LEFTOVER=0
  if [[ "$LEFTOVER" == "0" ]]; then
    pass "(e) HTML has no leftover {{...}} placeholders"
  else
    fail "(e) HTML still contains $LEFTOVER unrendered {{...}}"
  fi
fi

# ============================================================
# (f) i18n: HTML contains Japanese labels
# ============================================================

if grep -q 'プロジェクト' "$TMPDIR_TEST/cc.html"; then
  pass "(f) HTML contains 'プロジェクト' label"
else
  fail "(f) HTML missing 'プロジェクト' label (i18n)"
fi

if grep -q '判断待ち' "$TMPDIR_TEST/cc.html"; then
  pass "(f) HTML contains '判断待ち' label"
else
  fail "(f) HTML missing '判断待ち' label (i18n)"
fi

if grep -q '今 着手中のセッション' "$TMPDIR_TEST/cc.html"; then
  pass "(f) HTML contains '今 着手中のセッション' headline"
else
  fail "(f) HTML missing '今 着手中のセッション' headline"
fi

if grep -q 'Mission Control' "$TMPDIR_TEST/cc.html"; then
  pass "(f) HTML contains 'Mission Control' subtitle"
else
  fail "(f) HTML missing 'Mission Control' subtitle"
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo "========================================="
echo "Result: PASS=$PASS  FAIL=$FAIL"
echo "========================================="

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Failed:"
  for m in "${FAIL_MESSAGES[@]}"; do echo "  - $m"; done
  exit 1
fi
