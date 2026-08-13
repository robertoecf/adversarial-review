# Fallback chain

`lib/call-external.sh` attempts to reach an external partner in a fixed order,
with explicit logging of which one succeeded. The order is **driven by the
detected host**: the partner is always the OTHER agent, never the host.

## Critical rule

Call ONLY the FIRST available partner. Stop as soon as one succeeds. Do not
re-rank or fall through after success.

## Cross-host routing

| Detected host | Primary partner            | Secondary partner                  | Third partner                 | Tertiary fallback             | Last resort                   |
|---------------|----------------------------|------------------------------------|-------------------------------|-------------------------------|-------------------------------|
| `claude`, artifact=code (default) | Direct xAI, Grok 4.5 high | Codex (`gpt-5.6-luna` max) | Pi model chain | Antigravity model ladder | DEGRADED: host self-review |
| `claude`, artifact=plan | Codex (`gpt-5.6-luna` max) | Direct xAI, Grok 4.5 high | Pi model chain | Antigravity model ladder | DEGRADED: host self-review |
| `codex`, author=codex | Pi model chain, xAI OAuth Grok 4.5 xhigh first | Claude (`claude -p` Opus xhigh) | Direct xAI | Antigravity model ladder | DEGRADED: host self-review |
| `codex`, author=grok | Codex (`gpt-5.6-luna` max) | Claude (`claude -p` Opus xhigh) | Non-xAI Pi chain, DeepSeek then Kimi | Antigravity model ladder | DEGRADED: host self-review |
| `codex`, any other author | Codex (`gpt-5.6-luna` max) | Claude (`claude -p` Opus xhigh) | Non-xAI Pi chain, DeepSeek then Kimi | Antigravity model ladder | DEGRADED: host self-review |
| `grok`        | Codex (`gpt-5.6-luna` max) | Claude (`claude -p` Opus xhigh) | Non-xAI Pi chain, DeepSeek then Kimi, never Grok | Antigravity model ladder | DEGRADED: host self-review |
| `pi`          | Codex (`gpt-5.6-luna` max) | Claude (`claude -p` Opus xhigh) | Direct xAI | Antigravity model ladder | DEGRADED: host self-review |
| `unknown`     | Direct xAI | Pi model chain | none | Antigravity model ladder | DEGRADED: host self-review |

The official `openai/codex-plugin-cc` plugin (slash command
`/codex:adversarial-review`) is **not** required. We invoke `codex exec`
directly so the skill works regardless of whether the official plugin is
installed.

## Detection: primary partner

Host `claude` order is artifact-aware (user decision 2026-07-11, env
`ADVERSARIAL_REVIEW_ARTIFACT`, default `code`): code/diff reviews go to Grok
first because the diff is normally Codex-authored and Codex reviewing its own
code would be same-family; plan reviews go to Codex first because the plan is
architect(Claude)-authored.

Host `codex` order is author-aware through `ADVERSARIAL_REVIEW_AUTHOR`.
Canonical values are `codex`, `grok`, `claude`, `pi`, `user`, and `unknown`.
Aliases `sol` and `openai` map to `codex`, `xai` maps to `grok`, and
`anthropic` maps to `claude`, all case-insensitively. An invalid explicit value
logs a warning and becomes `unknown`. When omitted, artifact `plan` infers
`codex`; code and every other artifact infer `grok`.

### Codex (when host=claude and artifact=plan, or fallback for artifact=code)
```bash
which codex && test -f ~/.codex/auth.json && echo "CODEX_OK"
```
Run `codex login` once on a fresh machine. For ChatGPT-account auth, ensure
`forced_login_method = "chatgpt"` is set in `~/.codex/config.toml` (see
[`codex-integration.md`](codex-integration.md)).

The reviewer invocation pins `-m gpt-5.6-luna` and
`-c model_reasoning_effort=max`; the interactive Codex default is irrelevant
to this leg.

### Direct xAI through Grok CLI
```bash
which grok && grok models
```
Uses `grok-4.5 --reasoning-effort high`. Grok 4.5 is xAI's frontier model,
and high is the largest effort supported by the current Grok CLI. Preferred
auth is
`XAI_API_KEY`; this is direct xAI key auth, not OpenRouter.
See [`grok-integration.md`](grok-integration.md).

### Pi (primary when host=codex and author=codex, otherwise a fallback)
```bash
which pi && pi --version
```
Uses headless Pi with this default model chain:

```bash
xai-oauth/grok-4.5 --thinking xhigh
opencode-go/deepseek-v4-flash:xhigh
moonshotai/kimi-k3:xhigh
```

The first model is called as `pi -p --mode text --no-tools --no-session --model xai-oauth/grok-4.5 --thinking xhigh`. The `default` token is still supported as an explicit override, and then Pi is called without `--model`, so Pi's own configured provider, model, and thinking level decide that attempt. The Moonshot leg is Kimi K3 xhigh through direct Moonshot API via Pi provider `moonshotai`; it is not OpenRouter. When the detected host is Grok, or host Codex is reviewing any non-Codex authorship (`grok`, `claude`, `pi`, `user`, or `unknown`), the script forces the non-xAI suffix only, DeepSeek then Kimi, never Grok through Pi.

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

The plugin first runs `agy models`, then tries the best configured model that
is listed. The default ladder crosses Claude, Gemini, and GPT providers. A
quota or call failure advances to the next candidate. The standalone `gemini`
CLI is never used.

### Invocation
```bash
agy -p "$prompt" --print-timeout "${ADVERSARIAL_REVIEW_TIMEOUT:-300}s" --model "$model" --sandbox
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
