# Claude CLI integration

## Role in this plugin

On a Codex host, `claude -p` is T1 for Codex-, user- and unknown-authored
work (see the roster in SKILL.md). `lib/claude-reviewer.sh` builds the call:
`claude -p --model opus --effort xhigh` by default, with read-only tools.

For the full chain, see [`fallback-chain.md`](fallback-chain.md). For host
detection, see [`host-detection.md`](host-detection.md).

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

## Invocation pattern (built by `lib/claude-reviewer.sh`)

```bash
claude -p \
  --model opus --effort xhigh \
  <auth-mode flags> \
  --tools "Read,Grep,Glob" \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
  --no-session-persistence \
  --input-format text --output-format text \
  < prompt-file 2>>claude.err
```

Auth-mode flags (`ADVERSARIAL_REVIEW_CLAUDE_AUTH`):
- `api` (default): `--bare`, which skips hooks, plugins, auto-memory and
  CLAUDE.md discovery.
- `subscription`: `--setting-sources ""`, `--settings '{"disableAllHooks":true}'`,
  `--disable-slash-commands`. `--bare` is not used here because it drops the
  subscription login.

Why these flags:
- `--tools "Read,Grep,Glob"` lets the reviewer check claims against the
  checkout it runs from, without edits, shell or network.
- Empty strict MCP config: no connectors reach the reviewer.
- `--no-session-persistence`: each review is a fresh, unsaved session.
- `--model opus --effort xhigh`: a critique pass is not a hot path; override
  with `ADVERSARIAL_REVIEW_CLAUDE_MODEL` and `ADVERSARIAL_REVIEW_CLAUDE_EFFORT`.

## Key flags

| Flag | Purpose |
|---|---|
| `-p, --print` | Non-interactive: emit response and exit |
| `--model <name>` | `opus` / `sonnet` / specific version |
| `--effort <level>` | `low` / `medium` / `high` / `xhigh` / `max` |
| `--tools "Read,Grep,Glob"` | Read-only tool allowlist |
| `--bare` | api auth only: skip hooks, plugins, auto-memory |
| `--setting-sources ""` | subscription auth: ignore user/project settings |
| `--strict-mcp-config` | Use only the supplied (empty) MCP config |

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

- **Does not load CLAUDE.md or project settings.** The reviewer can read files
  in the checkout it runs from, but callers must still put the artifact and
  the relevant excerpts in the prompt.
- **Does not preserve conversation state.** Each `claude -p` is a fresh
  session. State that needs to persist across calls lives in
  the caller's own state; `--no-session-persistence` keeps nothing.
