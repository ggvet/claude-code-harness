---
name: harness-command-center
description: "Generate the Project Command Center (TOP) HTML — a 3-panel mission control view (sibling projects sidebar, current project main, drift/velocity rail) used as the entry point before drilling into per-task surfaces. Aggregates Plans.md, git tags, sibling projects under the parent dir, and recent commits. Use when user asks for: project overview, dashboard, mission control, command center, top page, プロジェクト全体, ダッシュボード, トップ画面. Do NOT load for: per-task plan brief, per-session progress, per-task acceptance — those are separate skills (harness-plan-brief / harness-progress / harness-accept)."
description-en: "Generate the Project Command Center (TOP) HTML — a 3-panel mission control view (sibling projects sidebar, current project main, drift/velocity rail) used as the entry point before drilling into per-task surfaces. Aggregates Plans.md, git tags, sibling projects under the parent dir, and recent commits. Use when user asks for: project overview, dashboard, mission control, command center, top page, プロジェクト全体, ダッシュボード, トップ画面. Do NOT load for: per-task plan brief, per-session progress, per-task acceptance — those are separate skills (harness-plan-brief / harness-progress / harness-accept)."
description-ja: "Project Command Center (TOP) HTML を生成する。3-panel mission control 構成 (sibling projects sidebar / 現プロジェクト main / drift・velocity rail) で、個別タスクの 3 surface に入る前のエントリポイント。Plans.md、git tag、sibling projects、直近 commits を集約。Use when: プロジェクト全体, ダッシュボード, トップ画面, mission control, command center。Do NOT load for: 単一タスクの Plan Brief / 単一セッションの Progress / 単一タスクの Accept (それぞれ別 skill)。"
allowed-tools: ["Read", "Write", "Bash"]
argument-hint: "[--out <path>] [--no-open] [--projects-root <path>]"
---

# Harness Command Center

Phase 65.6 (Project Command Center) — vibecoder ダッシュボードの **TOP 画面**。

Plan Brief / Progress Tracker / Acceptance Demo の 3 surface はそれぞれ「**1 タスクの詳細**」を示す。Command Center はその上位、**プロジェクト全体の俯瞰**を示す mission control。

参考: hermes-desktop / hermes-webui の 3-panel pattern (sessions sidebar + center work + control rail)。

## Quick Reference

| 入力 | 動作 |
|---|---|
| `/harness-command-center` | 現プロジェクトの TOP HTML を生成し開く |
| `/harness-command-center --no-open` | 生成のみ (browser 起動なし) |
| `/harness-command-center --out <path>` | 出力先指定 (default: `out/command-center.html`) |
| `/harness-command-center --projects-root <dir>` | sibling projects 親ディレクトリ指定 (default: 現 repo の親) |

## Mission

> 「いま自分は何を抱えていて、次にどこを見るべきか」を、
> ブラウザの 1 画面で 3 秒で把握できる **3-panel mission control** を生成する。

**やる**:
- Sibling projects を sidebar にリスト (現プロジェクトを active として先頭固定)
- 現プロジェクトの KPI (Phase / Tasks / Release / Cost) を main hero に表示
- 着手中セッションへの 3 surface 入口 (Plan / Progress / Accept) を main 中央に配置
- 直近 7 日の活動フィードを main 下部に並べる
- Cross-session drift / today's velocity / quick actions を right rail に集約

**やらない** (本 cycle):
- Multi-session 同時表示 (現状は 1 active session 前提)
- Real-time WebSocket 更新 (静的 HTML、再生成で更新)
- 多階層プロジェクト探索 (sibling = 1 階下のみ、再帰しない)

## Schema: command-center-snapshot.v1

詳細仕様: [schemas/command-center-snapshot.v1.schema.json](${CLAUDE_SKILL_DIR}/schemas/command-center-snapshot.v1.schema.json)

主要 fields:

```yaml
schema:                command-center-snapshot.v1
active_project:        string                  # 現プロジェクト名
all_systems_status:    green|amber|red         # 状態サマリ
active_phase_label:    string                  # "65" 等
tasks_done / total / pct:    int               # cc:完了 / 全件 / %
latest_release:        string                  # "v4.9.0" 等
projects[]:            sidebar 表示の sibling list
active_sessions[]:     現アクティブセッション (1 件想定)
activities[]:          直近 commits (max 8)
drift_alerts[]:        5 種固定 (scope-creep / time-overrun / repeated-failure / cost-warning / high-risk-file)
velocity_*:            commits today / yesterday、cost 等
```

## Execution Flow

### Step 0: PROJECT_NAME を取得

```bash
PROJECT_NAME="$(basename "$(git rev-parse --show-toplevel)" 2>/dev/null || echo 'current')"
```

### Step 1: snapshot を組み立て

```bash
SNAPSHOT_JSON="$(mktemp /tmp/command-center-XXXX.json)"
bash "${HARNESS_PLUGIN_ROOT}/scripts/command-center-compile.sh" \
  --project "$PROJECT_NAME" \
  --out "$SNAPSHOT_JSON"
```

`scripts/command-center-compile.sh` (Phase 65.6.1) が:
- `dirname $(git rev-parse --show-toplevel)` を sibling 親に
- Plans.md を解析 (cc:WIP / cc:TODO / cc:完了 集計)
- `git tag --sort=-creatordate | head -1` で latest release 取得
- `git log --since "today 00:00"` で velocity 集計
- 結果を `command-center-snapshot.v1` schema 準拠の JSON で stdout

### Step 2: HTML をレンダリング

```bash
OUT_PATH="${OUT_PATH:-out/command-center.html}"
mkdir -p "$(dirname "$OUT_PATH")"

bash "${HARNESS_PLUGIN_ROOT}/scripts/render-html.sh" \
  --template command-center \
  --data "$SNAPSHOT_JSON" \
  --out "$OUT_PATH"
```

### Step 3: ブラウザで開く

`--no-open` flag が**ない**場合のみ:

```bash
open "$OUT_PATH"   # macOS
# Linux: xdg-open "$OUT_PATH"
```

## Failure modes

| 状態 | 動作 |
|---|---|
| `git` 不在 / git repo 外 | branch / HEAD / latest_release を `unknown` で fallback |
| Plans.md が無い | tasks 0/0、active_phase_label = "?" |
| sibling projects 親が無い | projects 配列 = 現プロジェクト 1 件のみ |
| `jq` 不在 | exit 1 (clear error message) |

## Cross-project safety

`projects[]` には **basename のみ**を入れる。フルパス、絶対パス、environment 変数は含めない。
個別 project の中身 (Plans.md 等) は読まない (sidebar 表示用の metadata のみ)。

これにより 3 層 redaction (Phase 65.3) の対象外で安全に運用できる。

## Related

- `harness-plan-brief` (Phase 65.1.x) — TOP からドリルダウンする 1st surface
- `harness-progress` (Phase 65.4.x) — TOP からドリルダウンする 2nd surface
- `harness-accept` (Phase 65.2.x) — TOP からドリルダウンする 3rd surface
- 65.6.2 以降で multi-session 同時表示、real-time 更新を検討
