# Claude CLI integration

## Role in this plugin

Claude CLI is the Codex-host fallback after Pi fails. The skill sends
the wrapped prompt through `lib/call-external.sh`, which detects the host and
(if codex and Pi failed) shells out to `claude -p --model opus --effort xhigh`
in bare, prompt-only mode with no tools.

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
  --bare \
  --tools "" \
  --dangerously-skip-permissions \
  "<prompt>" \
  2>>err.log \
  </dev/null
```

Why `--model opus`:
- Adversarial review benefits from the strongest reasoning available;
  Opus is the highest-tier model in the Claude family for code analysis.

Why `--effort xhigh`:
- We want maximum reasoning budget on a critique pass - this is not a hot path.
- Plan / code review is exactly the kind of work that justifies xhigh.

Why `--dangerously-skip-permissions`:
- `claude -p` runs non-interactively; permission prompts cannot be answered.
- `--tools ""` removes tool access, so this flag cannot authorize file, shell,
  network, or repository actions. It only avoids an interactive deadlock.

Why `--bare --tools ""`:
- `--bare` skips hooks, plugins, and auto-memory.
- The reviewer receives only the supplied prompt and cannot inspect the current
  directory or inherited environment through tools.

Why `-p` (print mode):
- Synchronous subprocess; stdout = final response, exit code = success/fail.

## Key flags

| Flag                                    | Purpose                                          |
|-----------------------------------------|--------------------------------------------------|
| `-p, --print`                           | Non-interactive: emit response and exit          |
| `--model <name>`                        | `opus` / `sonnet` / specific version             |
| `--effort <level>`                      | `low` / `medium` / `high` / `xhigh` / `max`      |
| `--dangerously-skip-permissions`        | Skip approval prompts (required for `-p`)        |
| `--tools ""`                            | Disable all Claude tools                          |
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

`lib/call-external.sh` writes operational logs to
`${XDG_STATE_HOME:-$HOME/.local/state}/adversarial-review/claude.err`. The
parent directory is restricted to the current user. The file persists for
debugging; delete it to rotate.

## What this plugin does NOT do

- **Does not load repository context or CLAUDE.md.** `--bare --tools ""`
  makes the reviewer prompt-only. Callers must include every relevant excerpt
  in the prompt.
- **Does not preserve conversation state.** Each `claude -p` is a fresh
  session. State that needs to persist across calls lives in
  the caller's own state; bare mode disables auto-memory.
