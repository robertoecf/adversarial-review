# Codex CLI integration

## Role in this plugin

Codex CLI is the external partner for Claude plan review, Grok-authored artifacts on Codex, and the Grok host. The skill
sends the wrapped prompt through `lib/call-external.sh`, which detects the host
and, when Codex is selected, shells out to `codex exec` with GPT-6 Astra,
medium reasoning, and a read-only sandbox.

For each host and author route, see [`fallback-chain.md`](fallback-chain.md). For host detection, see
[`host-detection.md`](host-detection.md).

## Environment expectations

- **Binary**: `/opt/homebrew/bin/codex` (v0.121.0+ tested)
- **Auth**: `~/.codex/auth.json` with `auth_mode: "chatgpt"` for ChatGPT-account
  subscribers; `OPENAI_API_KEY` env var for API-key auth
- **Config**: `~/.codex/config.toml` (see "Required config" below)
- **Sandbox**: `--sandbox read-only` in this plugin (we never want Codex
  modifying files during review)
- **Reviewer model**: `gpt-6-astra`, pinned independently of the interactive
  Codex model
- **Reviewer effort**: `medium` by default; `high` when selected for auth, sensitive data, migrations, concurrency, or changes spanning multiple modules

## Required config - `forced_login_method`

⚠️ **Critical gotcha** for ChatGPT-account auth: without this line in
`~/.codex/config.toml`, `codex exec --json` (the path cc-connect and this
plugin both use) returns:

```
404 Not Found: Model not found gpt-5.4
url: https://chatgpt.com/backend-api/codex/responses
```

even though the interactive TUI works fine with the same auth. The fix:

```toml
# ~/.codex/config.toml
model = "gpt-6-astra"
model_reasoning_effort = "medium"
forced_login_method = "chatgpt"   # ← required for ChatGPT-account exec mode
```

The `forced_login_method` directive locks the model resolution to the
ChatGPT subscription endpoint that includes the configured model in its
catalog (the original 404 above was hit with `gpt-5.4`).
Tracking issues that surfaced this: openai/codex#14266, #14190, #11927.

The interactive config may remain on `gpt-6-astra`. The plugin overrides only
the external reviewer invocation to `gpt-6-astra` with medium reasoning by default.

If you only have an OpenAI API key (no ChatGPT subscription), instead set
`OPENAI_API_KEY` and skip `forced_login_method`.

## Detection

```bash
which codex && test -f ~/.codex/auth.json && echo "CODEX_OK" || echo "NO_CODEX"
```

## Invocation pattern (used by `lib/call-external.sh`)

```bash
codex exec -m gpt-6-astra -c model_reasoning_effort="${ADVERSARIAL_REVIEW_CODEX_EFFORT:-medium}" \
  --sandbox read-only --skip-git-repo-check "<prompt>" 2>>err.log
```

`ADVERSARIAL_REVIEW_CODEX_EFFORT` accepts only `medium` or `high`. Invalid
values exit `1` before any provider call. The architect selects `high` only for
auth, sensitive data, migrations, concurrency, or multi-module changes.

Why `--sandbox read-only`:
- Adversarial review must not modify files; `read-only` is the strict guarantee.
- Avoids accidental writes if the prompt accidentally instructs file changes.
- Faster start-up than `workspace-write` (no fs setup).

Why `--skip-git-repo-check`:
- The prompt content is the unit of review; whether the cwd is a git repo is
  irrelevant.

Why no `--full-auto`:
- `--full-auto` implies `workspace-write` - incompatible with read-only review.

## Key flags

| Flag                       | Purpose                                                   |
|----------------------------|-----------------------------------------------------------|
| `-s, --sandbox <MODE>`     | `read-only` (this plugin) / `workspace-write` / `danger-full-access` |
| `--skip-git-repo-check`    | Don't refuse if cwd isn't a git repo                      |
| `-c key=value`             | Override config (e.g. `-c forced_login_method=chatgpt`)   |
| `-m, --model`              | `gpt-6-astra` for this reviewer                           |
| `--ephemeral`              | Don't persist session files (overlapping with sandbox)    |
| `-o <file>`                | Write final agent message to file (alternative to stdout) |
| `--json`                   | JSONL event stream (cc-connect uses this)                 |

## Anti-recursion contract

`lib/call-external.sh` increments `ADVERSARIAL_REVIEW_DEPTH` before invoking
`codex exec`. Codex inherits env. If the prompt being reviewed somehow asks
Codex to invoke this skill again, the recursion guard in `call-external.sh`
refuses (exit 1). See `host-detection.md` for the full anti-recursion chain.

## Cleanup

`lib/call-external.sh` writes operational logs to
`${XDG_STATE_HOME:-$HOME/.local/state}/adversarial-review/codex.err`. The parent
directory is restricted to the current user. The file persists for debugging;
delete it to rotate.

## What this plugin does NOT do

- **Does not invoke `/codex:adversarial-review`** (the official Claude Code
  plugin from `openai/codex-plugin-cc`). That plugin is complementary, not
  required. We invoke `codex exec` directly so the skill works without the
  official plugin installed. If you want to use the official plugin, run it
  directly (`/codex:adversarial-review` in your Claude Code session).
- **Does not log in for you.** If `codex login` was never run, `auth.json` is
  empty and `codex exec` will refuse. Run `codex login` once before using
  this skill on a fresh machine.
