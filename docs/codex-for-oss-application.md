# Codex for Open Source — Application Draft

> Copy-paste source for the OpenAI **Codex for Open Source** application
> (<https://openai.com/form/codex-for-oss/>). The official form is an external,
> authenticated web form, so paste the answers below into it directly.
>
> 日本語メモ: 以下は OpenAI フォームに貼り付けるための英語ドラフトです。フォームの
> 実際の項目名と多少違う場合は、近い設問にこの内容を当てはめてください。各セクション
> 見出しの後ろに、対応しそうな日本語の補足を添えています。

---

## Applicant / Maintainer（応募者・メンテナ）

- **Name:** Chachamaru
- **GitHub:** https://github.com/Chachamaru127
- **Email:** _<fill in your contact email when submitting the form>_ (kept out of the
  public repo to avoid permanently publishing a personal address)
- **Role on the project:** Creator and sole core maintainer (owner of the repository,
  author of every release).

## Project（プロジェクト）

- **Project name:** Claude Code Harness
- **Repository:** https://github.com/Chachamaru127/claude-code-harness
- **License:** MIT
- **Primary languages:** Shell (orchestration), Go (native core engine), TypeScript (MCP server)
- **One-line description:** A disciplined Plan → Work → Review → Ship delivery loop for
  AI coding agents, with first-class, bounded execution paths for **Codex**, Claude Code,
  and OpenCode.

## What the project does（概要）

Claude Code Harness turns ad-hoc agentic coding into one repeatable operating path.
After install, the default workflow changes from "ask the agent to code" to a five-step
loop that any agent backend can drive:

1. write the spec and plan,
2. implement only the approved slice,
3. verify the result,
4. review independently,
5. package evidence for the PR or release.

It ships guardrails (a declarative R01–R13 rule engine), agent memory, parallel "team"
execution, and an evidence-backed review gate. Crucially, the *implementation backend is
pluggable* — Codex is one of the selectable engines, not an afterthought.

## Adoption & maintenance signals（採用・メンテナンス実績）

- ⭐ **2,228 stars**, 🍴 **223 forks** (public, MIT-licensed) — _as of 2026-05-30_.
- **Actively maintained:** created 2025-12, with frequent tagged releases — multiple
  releases per week (e.g. v4.13.0 → v4.13.1 → v4.13.2 across 2026-05-29 → 2026-05-30,
  _as of 2026-05-30_).
- Distributed for three agent ecosystems from a single source of truth: Claude Code
  (`.claude-plugin/`), **Codex CLI** (`.codex-plugin/plugin.json` + mirrored skills under
  `codex/.codex/skills/`), and OpenCode.
- Detailed, user-facing CHANGELOG / GitHub Releases with Before/After tables for every
  change.

## How the project already uses Codex（Codex の利用実態）

This is not a project that *would* adopt Codex — it already builds Codex into its core
maintainer workflows:

- **Codex as a selectable implementation backend** ("brain = reasoning model, body =
  Codex"): `HARNESS_IMPL_BACKEND=codex` routes the implementation (worker) role to Codex
  while keeping review/advisor roles on a separate reviewer model to prevent self-review.
- **`scripts/codex-companion.sh`** — a wrapper that delegates whole tasks to Codex via the
  official `openai/codex-plugin-cc` plugin: `task --write` (implementation/debugging),
  `review` / `review --base <ref>` (code review), and `adversarial-review` (challenging
  design decisions), plus job management (`setup` / `status` / `result` / `cancel`).
- **`/codex:*` user commands** for ad-hoc Codex delegation (rescue, review,
  adversarial-review).
- **Codex-native skill variants** under `skills-codex/` and a full mirror in
  `codex/.codex/skills/`.
- **Benchmark harness** for Codex-driven runs: `benchmarks/breezing-codex-test/`.
- **Governed integration:** raw `codex exec` is banned in favor of the official plugin;
  the verdict schema is mapped to the harness review schema; a documented policy lives in
  `.claude/rules/codex-cli-only.md`.

## How we would use the Codex credits / access（クレジット・アクセスの使途）

Mapped directly to the program's stated use cases:

- **PR review:** Run `codex-companion.sh review` and `adversarial-review` automatically on
  incoming pull requests, surfacing structured findings (critical / major / recommendation)
  before a human review pass.
- **Maintainer automation:** Use Codex as the implementation backend for routine,
  well-scoped maintenance tasks (bug fixes, refactors, dependency bumps) through the
  harness's guarded worktree → diff-review → cherry-pick path, so every Codex change still
  passes the R01–R13 guardrails and the evidence gate.
- **Release workflows:** Drive changelog drafting, consistency checks, and release-evidence
  packaging through Codex-backed runs.
- **Self-referential improvement:** The harness improves itself ("uses the harness to
  improve the harness"), so credits directly accelerate development *and* validate Codex on
  a real, non-trivial codebase that thousands of other developers depend on.

## Why this project matters to the ecosystem（エコシステムにとっての重要性）

Claude Code Harness is one of the most-adopted open frameworks for *disciplined* agentic
software delivery, and it is explicitly multi-agent: it gives Codex users a production-grade
Plan → Work → Review → Ship loop with guardrails, memory, and evidence-based review out of
the box. Funding it (a) strengthens a widely used OSS tool that 2,200+ developers already
depend on, and (b) deepens a real, well-governed Codex integration that demonstrates Codex
working safely inside a structured, reviewable workflow — a reference implementation other
maintainers can copy.

---

### Quick fact sheet (for any short-answer fields)

| Field | Value |
|-------|-------|
| Project | Claude Code Harness |
| Repo | https://github.com/Chachamaru127/claude-code-harness |
| License | MIT |
| Stars / Forks | 2,228 / 223 (as of 2026-05-30) |
| Maintainer | Chachamaru (https://github.com/Chachamaru127) |
| Existing Codex usage | Selectable backend, PR review, adversarial review, Codex CLI plugin distribution, benchmarks |
| Intended Codex use | PR review · maintainer automation · release workflows · self-hosted dogfooding |
