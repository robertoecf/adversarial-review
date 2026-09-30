# Fallback chain

`lib/call-external.sh` attempts to reach an external partner in a fixed order,
with explicit logging of which one succeeded. The order is **driven by the
detected host**: the partner is always the OTHER agent, never the host.

## Critical rule

Call ONLY the FIRST available partner. Stop as soon as one succeeds. Do not
re-rank or fall through after success.

## Cross-host routing

| Detected host | Ordered route | Last resort |
|---------------|---------------|-------------|
| `claude`, author=claude (default) | T1 Astra high via Pi, `codex exec`; T2 Pi chain; T3 Gemini | DEGRADED |
| `claude`, author=codex | T1 is the host main loop (inline); wrapper gives T2 Pi chain, T3 Gemini (never Codex) | DEGRADED |
| `codex`, author=codex/user/unknown | T1 `claude -p`; T2 Pi chain; T3 Gemini | DEGRADED |
| `codex`, author=grok | T1 Codex Astra; T2 non-xAI Pi chain; T3 Gemini | DEGRADED |
| `codex`, author=claude/pi | T1 Codex Astra; T2 Pi chain; T3 Gemini | DEGRADED |
| `grok` | Codex Astra, Gemini | DEGRADED |
| `pi` | Codex Astra, Claude, direct xAI, Gemini | DEGRADED |
| `unknown` | Direct xAI, Pi chain, Gemini | DEGRADED |

T2 Pi chain: `opencode-go/deepseek-v4.1-flash:xhigh`, `opencode-go/glm-5.3:high`,
then `xai-oauth/grok-4.7:high`. Pi runs with read-only tools
(`read,grep,find,ls`); Claude runs with `Read,Grep,Glob`.


The official `openai/codex-plugin-cc` plugin (slash command
`/codex:adversarial-review`) is **not** required. We invoke `codex exec`
directly so the skill works regardless of whether the official plugin is
installed.

## Detection: primary partner

Host `claude` order is author-aware (user decision 2026-09-28, env
`ADVERSARIAL_REVIEW_AUTHOR`, default `claude`): Claude-authored code and plans
go to T1 Astra high via Pi, then `codex exec`, then T2 and T3. For author
`codex`, the Claude main loop is T1 and reviews inline with tools; the wrapper
only supplies T2/T3 second opinions and never returns to Codex. Author `grok`
skips the xAI leg of T2.

Host `codex` order is author-aware through `ADVERSARIAL_REVIEW_AUTHOR`.
Canonical values are `codex`, `grok`, `claude`, `pi`, `user`, and `unknown`.
Aliases `sol`, `openai`, and `astra` map to `codex`, `xai` maps to `grok`, and
`anthropic` maps to `claude`, all case-insensitively. An invalid explicit value
logs a warning and becomes `unknown`. When omitted, every artifact infers
`codex`, matching the Astra interactive default.

### Codex (host=claude when the author is not codex)
```bash
which codex && test -f ~/.codex/auth.json && echo "CODEX_OK"
```
Run `codex login` once on a fresh machine. For ChatGPT-account auth, ensure
`forced_login_method = "chatgpt"` is set in `~/.codex/config.toml` (see
[`codex-integration.md`](codex-integration.md)).

The reviewer invocation pins `-m gpt-6-astra` and defaults to
`-c model_reasoning_effort=medium` (`high` on host Claude). The architect sets
`ADVERSARIAL_REVIEW_CODEX_EFFORT=high` only for auth, sensitive data,
migrations, concurrency, or multi-module changes. Other values fail before
provider dispatch.

### Direct xAI through Grok CLI
```bash
which grok && grok models
```
Uses `grok-4.7 --reasoning-effort xhigh`. Grok 4.7 is xAI's frontier model,
and xhigh is supported by the current Grok CLI. Preferred
auth is
`XAI_API_KEY`; this is direct xAI key auth, not OpenRouter.
See [`grok-integration.md`](grok-integration.md).

### Pi (primary on Codex except for Grok-authored artifacts, otherwise a fallback)
```bash
which pi && pi --version
```
Uses headless Pi with read-only tools and the T2 chain from the SKILL.md roster:

```bash
opencode-go/deepseek-v4.1-flash:xhigh
opencode-go/glm-5.3:high
xai-oauth/grok-4.7:high
```

The `default` token is still supported as an explicit override; Pi is then
called without `--model`. On host Claude, Claude-authored work first tries
`openai-codex/gpt-6-astra:high` through the same Pi call (T1).

See [`pi-integration.md`](pi-integration.md). The call must stay in the caller's
repo/worktree root on this machine because the opencode-go key can resolve
through Doppler's current-directory scope.

### Claude (secondary for host=codex)
```bash
which claude
```
Auth is managed by the Claude desktop / `claude login` flow. `claude -p`
fails fast if not authenticated.

## Antigravity model ladder

### Detection
```bash
command -v agy || test -x "$HOME/.local/bin/agy"
```

The plugin first runs `agy models`, then tries the listed Gemini models in
order: `gemini-3.8-flash-high`, `gemini-3.7-flash-high`, and
`gemini-3.1-pro-high`. A quota or call failure advances to the next candidate.
The standalone `gemini` CLI is never used.


### Invocation
```bash
agy -p "$prompt" --print-timeout "${ADVERSARIAL_REVIEW_TIMEOUT:-300}s" --model "$model" --sandbox --mode plan
```

## Degraded mode

If all external paths fail or are unavailable:

- `lib/call-external.sh` exits with code `2` (not `0`, not `1`).
- Stdout begins with the literal banner:
  ```
  ⚠️  DEGRADED MODE - Cross-host principle violated
  ```
- The skill calling `call-external.sh` MUST surface this banner at the top
  of the user-facing output (see SKILL.md format examples).
- The output is single-perspective (host self-review). Treat with appropriate
  skepticism.

This is intentional. Silently auto-reviewing would be the worst outcome.
The user should know the principle was bypassed.

## Forced degraded for testing

To test the degraded path **without** breaking auth:

```bash
echo "test prompt" | ADVERSARIAL_REVIEW_FORCE_DEGRADED=1 \
  bash lib/call-external.sh
```

This skips all externals and emits the banner directly.

## Anti-recursion (interaction with cascade)

`ADVERSARIAL_REVIEW_DEPTH` guards cross-agent recursion across Claude, Codex,
Grok, and Pi. The Antigravity fallback does not decrement or re-check depth
because Antigravity does not host this skill.

## Cleanup

Operational logs are appended under
`${XDG_STATE_HOME:-$HOME/.local/state}/adversarial-review/`, in `codex.err`,
`claude.err`, `grok.err`, `pi.err`, and `antigravity.err`. The directory is
restricted to the current user. Delete the files to rotate. The script does
not auto-rotate; persistence is intentional.

## What this chain does NOT do

- **No Anthropic API key auth path.** Claude side uses the OAuth-managed CLI.
  If you have only an `ANTHROPIC_API_KEY`, `claude` CLI handles it
  transparently. No special handling here.
- **No OpenAI API key auth for Codex.** Codex CLI handles `OPENAI_API_KEY`
  vs ChatGPT subscription internally; we just call `codex exec`.
- **No retry on the same model.** If Codex stalls, we continue the fallback
  chain. Codex stalls (rare; verified) suggest backend issue, not transient. Retry is
  unlikely to help in the timeout we have.
