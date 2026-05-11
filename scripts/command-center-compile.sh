#!/usr/bin/env bash
# scripts/command-center-compile.sh
# Phase 65.6.1 - Project Command Center (TOP) snapshot compiler
#
# Purpose:
#   Sibling projects + 現プロジェクトの状態 + 最近の活動を集約し、
#   command-center-snapshot.v1 schema 準拠の JSON を出力する。
#   harness-command-center skill / render-html.sh の入力になる。
#
# Usage:
#   command-center-compile.sh --project <name> [--projects-root <path>]
#                             [--plans <path>] [--out -|<path>]
#                             [--max-projects <N>] [--max-activities <N>]
#
# Schema: skills/harness-command-center/schemas/command-center-snapshot.v1.schema.json
#
# データソース:
#   - projects[]            : --projects-root 直下の sibling dirs (default: 現 repo の親)
#   - active_phase / tasks  : Plans.md の cc:WIP / cc:TODO / cc:完了 集計
#   - latest_release        : git tag --sort=-creatordate | head -1
#   - branch / head         : git symbolic-ref / git rev-parse
#   - velocity_*            : git log --since "today 00:00" / "yesterday 00:00"
#   - drift_alerts          : 5 種固定 (現状全て success、将来動的化)
#
# 設計方針:
#   - 取得失敗時は空文字 / 0 で fallback (UI 側で「不明」表示)
#   - jq があれば JSON マージ、無ければ printf で組み立て
#   - 文字列内の " と \ は jq -Rs で安全 escape

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: command-center-compile.sh --project <name> [options]

Required:
  --project <name>           現プロジェクト名

Optional:
  --projects-root <path>     sibling projects 親ディレクトリ
                             default: $(dirname $(git rev-parse --show-toplevel))
  --plans <path>             Plans.md パス (default: ./Plans.md)
  --out -|<path>             出力先 (- = stdout、default: stdout)
  --max-projects <N>         sidebar に表示する project 上限 (default: 10)
  --max-activities <N>       activity feed の上限 (default: 8)

Exit: 0=success / 1=runtime error / 2=usage error
USAGE
  exit 2
}

PROJECT=""
PROJECTS_ROOT=""
PLANS_PATH="Plans.md"
OUT_PATH="-"
MAX_PROJECTS=10
MAX_ACTIVITIES=8

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)         PROJECT="${2:-}";         shift 2 ;;
    --projects-root)   PROJECTS_ROOT="${2:-}";   shift 2 ;;
    --plans)           PLANS_PATH="${2:-}";      shift 2 ;;
    --out)             OUT_PATH="${2:-}";        shift 2 ;;
    --max-projects)    MAX_PROJECTS="${2:-}";    shift 2 ;;
    --max-activities)  MAX_ACTIVITIES="${2:-}";  shift 2 ;;
    -h|--help)         usage ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage ;;
  esac
done

[[ -z "$PROJECT" ]] && { echo "ERROR: --project required" >&2; exit 2; }

if ! command -v jq >/dev/null; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

# --- Resolve PROJECTS_ROOT ---
if [[ -z "$PROJECTS_ROOT" ]]; then
  if REPO_TOP="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    PROJECTS_ROOT="$(dirname "$REPO_TOP")"
  else
    PROJECTS_ROOT="."
  fi
fi

# --- Resolve git context (for active project) ---
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo 'main')"
HEAD_SHORT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
LATEST_RELEASE="$(git tag --sort=-creatordate 2>/dev/null | head -1 || echo 'unknown')"
LATEST_RELEASE_DATE=""
if [[ -n "$LATEST_RELEASE" && "$LATEST_RELEASE" != "unknown" ]]; then
  LATEST_RELEASE_DATE="$(git log -1 --format=%ad --date=short "$LATEST_RELEASE" 2>/dev/null || echo '')"
fi

# --- Plans.md aggregation (reuse progress-snapshot pattern) ---
TASKS_DONE=0
TASKS_WIP=0
TASKS_TODO=0
TASKS_TOTAL=0
TASKS_PCT=0
ACTIVE_PHASE_LABEL=""
ACTIVE_PHASE_SUBTITLE=""

if [[ -f "$PLANS_PATH" ]]; then
  # Plans.md の table row を grep
  # Status column の cc: prefix で分類
  while IFS= read -r line; do
    case "$line" in
      *"cc:完了"*) TASKS_DONE=$((TASKS_DONE+1)) ;;
      *"cc:WIP"*)  TASKS_WIP=$((TASKS_WIP+1)) ;;
      *"cc:TODO"*) TASKS_TODO=$((TASKS_TODO+1)) ;;
    esac
  done < <(grep -E '^\| [0-9]+(\.[0-9]+)*' "$PLANS_PATH" 2>/dev/null || true)
  TASKS_TOTAL=$((TASKS_DONE + TASKS_WIP + TASKS_TODO))
  if [[ $TASKS_TOTAL -gt 0 ]]; then
    TASKS_PCT=$(( (TASKS_DONE * 100) / TASKS_TOTAL ))
  fi
  # 直近の Phase 番号を Plans.md headline (## Phase N) から推定
  ACTIVE_PHASE_LABEL="$(grep -oE '^## Phase [0-9]+' "$PLANS_PATH" 2>/dev/null | tail -1 | grep -oE '[0-9]+' || echo '?')"
  ACTIVE_PHASE_SUBTITLE="$(grep -oE '^## Phase [0-9]+:.*' "$PLANS_PATH" 2>/dev/null | tail -1 | sed -E 's/^## Phase [0-9]+:\s*//' | head -c 40 || echo '')"
fi

# --- All systems status ---
ALL_SYSTEMS_STATUS="green"
ALL_SYSTEMS_LABEL="All systems green"
if [[ $TASKS_WIP -gt 0 ]]; then
  ALL_SYSTEMS_STATUS="amber"
  ALL_SYSTEMS_LABEL="${TASKS_WIP} task(s) in flight"
fi

# --- Sibling projects (sidebar list) ---
projects_json="[]"
if [[ -d "$PROJECTS_ROOT" ]]; then
  # 現プロジェクトを先頭に、他は last-modified 順
  current_project_dir=""
  if [[ -d "$PROJECTS_ROOT/$PROJECT" ]]; then
    current_project_dir="$PROJECTS_ROOT/$PROJECT"
  fi

  # 他 project を mtime 降順で集める (max-1 件)
  others_remaining=$((MAX_PROJECTS - 1))
  others_json="[]"
  if [[ $others_remaining -gt 0 ]]; then
    while IFS= read -r dir; do
      [[ -z "$dir" ]] && continue
      base="$(basename "$dir")"
      # Skip current, hidden, backup, docs
      [[ "$base" == "$PROJECT" ]] && continue
      [[ "$base" == _* ]] && continue
      [[ "$base" == "docs" ]] && continue

      # Days ago (最終更新からの経過日数)
      mtime_epoch="$(stat -f %m "$dir" 2>/dev/null || stat -c %Y "$dir" 2>/dev/null || echo 0)"
      now_epoch="$(date +%s)"
      days_ago=$(( (now_epoch - mtime_epoch) / 86400 ))
      if [[ $days_ago -le 1 ]]; then
        sub_label="$(date -r "$mtime_epoch" '+%H:%M' 2>/dev/null || echo 'recently')"
        sub_label="updated ${sub_label}"
        dot="green"
      elif [[ $days_ago -le 7 ]]; then
        sub_label="idle · ${days_ago} days ago"
        dot="grey"
      else
        weeks=$((days_ago / 7))
        sub_label="idle · ${weeks} week(s) ago"
        dot="grey"
      fi

      others_json="$(echo "$others_json" | jq --arg name "$base" --arg sub "$sub_label" --arg dot "$dot" \
        '. + [{name: $name, is_active_label: "", status_dot_class: $dot, subtitle: $sub}]')"
    done < <(find "$PROJECTS_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
              | xargs -I{} stat -f "%m %N" {} 2>/dev/null \
              | sort -rn | head -n "$others_remaining" | awk '{$1=""; sub(/^ /, ""); print}')
  fi

  # Current project を先頭に prepend
  current_subtitle="${LATEST_RELEASE} · ${TASKS_PCT}% · just now"
  current_obj="$(jq -n --arg n "$PROJECT" --arg s "$current_subtitle" \
    '{name: $n, is_active_label: "ACTIVE NOW", status_dot_class: "coral", subtitle: $s}')"
  projects_json="$(echo "$others_json" | jq --argjson cur "$current_obj" '[$cur] + .')"
fi

projects_count="$(echo "$projects_json" | jq 'length')"

# --- Active sessions (1 = current session) ---
session_short="$(date +%s | sha1sum | head -c 8 2>/dev/null || echo 'session')"
active_sessions_json="$(jq -n --arg t "現セッション" --arg s "$session_short" \
  '[{title: $t, session_id_short: $s, started_label: "in progress", progress_pct: '"$TASKS_PCT"'}]')"

# --- Activity feed: 直近の commits ---
activities_json="[]"
if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
  while IFS=$'\t' read -r time msg; do
    [[ -z "$time" ]] && continue
    kind="info"
    case "$msg" in
      release*|*"v"[0-9]*) kind="release" ;;
      feat*|fix*)          kind="plan" ;;
      chore*"完了"*)       kind="milestone" ;;
      docs*)               kind="info" ;;
      *)                   kind="session" ;;
    esac
    # Escape via jq
    activities_json="$(echo "$activities_json" | jq --arg t "$time" --arg m "$msg" --arg k "$kind" \
      '. + [{time: $t, text: $m, kind: $k}]')"
  done < <(git log --pretty=format:'%ad%x09%s' --date=format:'%H:%M' -n "$MAX_ACTIVITIES" 2>/dev/null || true)
fi

# --- Drift alerts (Phase 65.6 では固定 5 種、将来動的化) ---
drift_alerts_json='[
  {"kind":"scope-creep",      "count":0, "severity_class":"success", "label":"問題なし"},
  {"kind":"time-overrun",     "count":0, "severity_class":"success", "label":"予定以内"},
  {"kind":"repeated-failure", "count":0, "severity_class":"success", "label":"再試行ゼロ"},
  {"kind":"cost-warning",     "count":0, "severity_class":"success", "label":"予算内"},
  {"kind":"high-risk-file",   "count":0, "severity_class":"success", "label":"監視対象なし"}
]'

# --- Velocity stats ---
TODAY_START="$(date '+%Y-%m-%d 00:00')"
YESTERDAY_START="$(date -v-1d '+%Y-%m-%d 00:00' 2>/dev/null || date -d 'yesterday' '+%Y-%m-%d 00:00' 2>/dev/null || echo "$TODAY_START")"
COMMITS_TODAY=0
COMMITS_YESTERDAY=0
if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
  COMMITS_TODAY="$(git log --since="$TODAY_START" --pretty=oneline 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
  COMMITS_YESTERDAY="$(git log --since="$YESTERDAY_START" --until="$TODAY_START" --pretty=oneline 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
fi

# --- Active project subtitle (CLAUDE.md の Project Overview から) ---
SUBTITLE="(no description)"
if [[ -f "CLAUDE.md" ]]; then
  SUBTITLE="$(grep -A1 -E '^## Project Overview' CLAUDE.md 2>/dev/null | tail -1 | sed -E 's/^\*\*//; s/\*\*//; s/[\[\]]//g' | head -c 120 || echo '(no description)')"
fi
[[ -z "$SUBTITLE" ]] && SUBTITLE="(no description)"

# --- Generated at ---
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# --- Compose final JSON ---
SNAPSHOT="$(jq -n \
  --arg project "$PROJECT" \
  --arg subtitle "$SUBTITLE" \
  --arg sys_status "$ALL_SYSTEMS_STATUS" \
  --arg sys_label "$ALL_SYSTEMS_LABEL" \
  --arg branch "$BRANCH" \
  --arg head "$HEAD_SHORT" \
  --arg session "$session_short" \
  --arg phase "$ACTIVE_PHASE_LABEL" \
  --arg phase_sub "$ACTIVE_PHASE_SUBTITLE" \
  --argjson done "$TASKS_DONE" \
  --argjson total "$TASKS_TOTAL" \
  --argjson pct "$TASKS_PCT" \
  --arg release "$LATEST_RELEASE" \
  --arg release_date "$LATEST_RELEASE_DATE" \
  --argjson cost_so_far 0 \
  --argjson cost_est 0 \
  --argjson cost_pct 0 \
  --argjson projects "$projects_json" \
  --argjson projects_count "$projects_count" \
  --argjson sessions "$active_sessions_json" \
  --arg cur_title "現セッション" \
  --arg cur_subtitle "$ACTIVE_PHASE_SUBTITLE" \
  --arg cur_hash "session-$session_short" \
  --arg pending_msg "現在ユーザー判断待ちのアイテムはありません" \
  --argjson activities "$activities_json" \
  --argjson alerts "$drift_alerts_json" \
  --argjson commits_today "$COMMITS_TODAY" \
  --argjson commits_yesterday "$COMMITS_YESTERDAY" \
  --arg audit_log ".claude/state/audit/cross-project-audit.jsonl" \
  --arg gen_at "$GENERATED_AT" \
  '{
    schema: "command-center-snapshot.v1",
    active_project: $project,
    active_project_subtitle: $subtitle,
    all_systems_status: $sys_status,
    all_systems_label: $sys_label,
    branch: $branch,
    head_short: $head,
    session_short: $session,
    active_phase_label: $phase,
    active_phase_subtitle: $phase_sub,
    tasks_done: $done,
    tasks_total: $total,
    tasks_pct: $pct,
    latest_release: $release,
    latest_release_date: $release_date,
    cost_so_far_usd: $cost_so_far,
    cost_estimate_usd: $cost_est,
    cost_pct: $cost_pct,
    projects_count: $projects_count,
    projects: $projects,
    active_sessions_count: ($sessions | length),
    active_sessions: $sessions,
    current_session_title: $cur_title,
    current_session_subtitle: $cur_subtitle,
    current_session_user_request_hash_short: $cur_hash,
    pending_decisions_count: 0,
    pending_decisions_message: $pending_msg,
    activities: $activities,
    drift_alerts: $alerts,
    velocity_commits_today: $commits_today,
    velocity_commits_yesterday: $commits_yesterday,
    velocity_decisions_today: 0,
    velocity_decisions_label: "(plan→ship)",
    velocity_cost_today: 0,
    audit_log_path: $audit_log,
    generated_at: $gen_at
  }')"

if [[ "$OUT_PATH" == "-" ]]; then
  printf '%s\n' "$SNAPSHOT"
else
  printf '%s\n' "$SNAPSHOT" > "$OUT_PATH"
fi
