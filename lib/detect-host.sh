#!/usr/bin/env bash
# detect-host.sh: identify which agent host this script runs under.
#
# Output: prints exactly one of: "claude", "codex", "grok", "pi", "unknown" to stdout
# Exit:   0 if claude/codex/grok/pi detected, 1 if unknown
#
# Detection priority (cross-host principle: "the partner reviews, never the host"):
#   1. ADVERSARIAL_REVIEW_HOST override (explicit user/test override always wins)
#   2. Grok Build CLI env markers (GROK_HOME / GROK_LOG_FILE / GROK_AGENT_SECRET)
#   3. Codex env markers (CODEX_THREAD_ID / CODEX_CI, only Codex sets these,
#      and they do NOT leak when Codex is launched from Claude)
#   4. Pi env markers (PI_CODING_AGENT)
#   5. Claude Code env markers (CLAUDE_CODE_ENTRYPOINT / CLAUDE_AGENT_SDK_VERSION,
#      these DO leak from Claude into nested Codex processes, hence checked
#      after Codex)
#   6. Process-tree walk (innermost host wins; immune to env leak)
#
# When called from inside `codex exec` launched by Claude, env leaks Claude vars
# but Codex vars are also set; rule 3 wins → returns "codex". Verified.

set -u  # strict on unset; explicit defaults below

# 1. Manual override (escape hatch for sandboxes, future hosts, tests)
if [ -n "${ADVERSARIAL_REVIEW_HOST:-}" ]; then
  echo "$ADVERSARIAL_REVIEW_HOST"
  exit 0
fi

# 2. Grok Build CLI env markers
if [ -n "${GROK_HOME:-}" ] || [ -n "${GROK_LOG_FILE:-}" ] || [ -n "${GROK_AGENT_SECRET:-}" ]; then
  echo grok
  exit 0
fi

# 3. Codex env markers (highest specificity, only Codex sets these)
if [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_CI:-}" ]; then
  echo codex
  exit 0
fi

# 4. Pi env markers
if [ -n "${PI_CODING_AGENT:-}" ]; then
  echo pi
  exit 0
fi

# 5. Claude Code env markers
if [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ] || [ -n "${CLAUDE_AGENT_SDK_VERSION:-}" ]; then
  echo claude
  exit 0
fi

# 6. Process-tree fallback: walk PPIDs, return on first known host
pid=$$
for _ in 1 2 3 4 5 6 7 8; do
  if [ -z "${pid:-}" ] || [ "$pid" = "1" ] || [ "$pid" = "0" ]; then
    break
  fi
  comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ' | sed 's|.*/||')
  case "$comm" in
    codex|codex-cli)
      echo codex
      exit 0
      ;;
    claude|claude-code)
      echo claude
      exit 0
      ;;
    grok|grok-build)
      echo grok
      exit 0
      ;;
    pi)
      echo pi
      exit 0
      ;;
  esac
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
done

echo unknown
exit 1
