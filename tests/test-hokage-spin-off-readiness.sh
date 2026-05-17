#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT_DIR/docs/hokage-spin-off-readiness.md"
FAILED=0

require_fixed() {
  local pattern="$1"
  if ! grep -Fq -- "$pattern" "$DOC"; then
    echo "missing required readiness pattern: $pattern"
    FAILED=1
  fi
}

require_gate_result() {
  local gate="$1"
  local result="$2"
  require_fixed "| ${gate} | ${result} |"
}

require_fixed "No public spin-off yet."
require_fixed "Last Verification Snapshot"
require_fixed "PASS locally with non-blocking warnings"
require_fixed "Runtime auto-routing proof is explicitly out of scope for this phase"
require_fixed "CI run evidence still requires pushing the branch before a release tag"

require_gate_result "Claude Code adapter" "PARTIAL"
require_gate_result "Codex adapter" "PASS"
require_gate_result "OpenCode adapter" "PASS"
require_gate_result "Capability matrix" "PASS"
require_gate_result "Bootstrap routing" "PASS"
require_gate_result "Release preflight" "PASS"
require_gate_result "Positioning" "PASS"

require_fixed '`./tests/validate-plugin.sh` | PASS'
require_fixed '`bash tests/test-codex-package.sh` | PASS'
require_fixed '`node scripts/validate-opencode.js` | PASS'
require_fixed '`bash scripts/sync-skill-mirrors.sh --check` | PASS'
require_fixed '`bash tests/test-tool-capability-matrix.sh` | PASS'
require_fixed '`bash tests/test-bootstrap-routing-contract.sh` | PASS'
require_fixed '`bash scripts/release-preflight.sh` | PASS locally'

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo "test-hokage-spin-off-readiness: ok"
