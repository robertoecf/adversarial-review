# Claude CLI integration

## Role in this plugin

Claude CLI is the Codex-host fallback after Pi fails. The skill sends
the wrapped prompt through `lib/call-external.sh`, which detects the host and
(if codex and Pi failed) shells out to `claude -p --model opus --effort xhigh`.

For the full chain (claude -> grok -> pi/opencode-go -> Antigravity -> degraded), see
[`fallback-chain.md`](fallback-chain.md). For host detection, see
[`host-detection.md`](host-detection.md).

## Environment expectations

- **Binary**: `/Users/<you>/.local/bin/claude` (or wherever `which claude`
  resolves; v2.1.x tested)
- **Auth**: Anthropic OAuth via Claude Desktop (`CLAUDE_CODE_OAUTH_TOKEN`
  managed by host) OR `ANTHROPIC_API_KEY` env var
- **Config**: `~/.claude/settings.json` (only relevant if you've customized
  effort/permissions defaults)

## Detection

```bash
which claude || echo "NO_CLAUDE"
```

The CLI itself manages its auth - if not logged in, the call will fail loudly
rather than hang.

## Invocation pattern (used by `lib/call-external.sh`)

```bash
claude -p \
  --model opus \
  --effort xhigh \
  --dangerously-skip-permissions \
  "<prompt>" \
  2>>err.log
```

Why `--model opus`:
- Adversarial review benefits from the strongest reasoning available;
  Opus is the highest-tier model in the Claude family for code analysis.

Why `--effort xhigh`:
- We want maximum reasoning budget on a critique pass - this is not a hot path.
- Plan / code review is exactly the kind of work that justifies xhigh.

Why `--dangerously-skip-permissions`:
- `claude -p` runs non-interactively; permission prompts cannot be answered.
- The prompt itself is treated as user input (trusted); review is read-only
  in spirit, the flag avoids interactive deadlock.

Why `-p` (print mode):
- Synchronous subprocess; stdout = final response, exit code = success/fail.

## Key flags

| Flag                                    | Purpose                                          |
|-----------------------------------------|--------------------------------------------------|
| `-p, --print`                           | Non-interactive: emit response and exit          |
| `--model <name>`                        | `opus` / `sonnet` / specific version             |
| `--effort <level>`                      | `low` / `medium` / `high` / `xhigh` / `max`      |
| `--dangerously-skip-permissions`        | Skip approval prompts (required for `-p`)        |
| `--add-dir <path>...`                   | Grant access to additional dirs (for context)    |
| `--append-system-prompt <text>`         | Add to default system prompt                     |
| `--bare`                                | Minimal mode - skip hooks, plugins, auto-memory  |

## Anti-recursion contract

`lib/call-external.sh` increments `ADVERSARIAL_REVIEW_DEPTH` before invoking
`claude -p`. The launched Claude inherits the env. If the launched Claude
auto-triggers this skill (because the prompt happens to mention "adversarial
review"), the recursion guard in `call-external.sh` refuses (exit 1). See
`host-detection.md` for full anti-recursion chain.

## Cleanup

`lib/call-external.sh` writes operational logs to `/tmp/call-external-claude.err`.
That file persists by design - useful for debugging. To rotate, just delete it.

## What this plugin does NOT do

- **Does not load CLAUDE.md from the user's repo by default.** `claude -p`
  with no `--add-dir` only sees the current working directory. If the prompt
  needs access to other dirs (worktrees, sibling repos), the skill should
  pass them via `--add-dir <path>` - but `lib/call-external.sh` does not do
  this automatically. SKILLs that need multi-dir context should construct the
  call themselves or ask the user.
- **Does not preserve conversation state.** Each `claude -p` is a fresh
  session. State that needs to persist across calls lives in
  `~/.claude/projects/<cwd>/memory/` (auto-memory).
