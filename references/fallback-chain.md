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
| `claude`      | Codex (`codex exec`)       | Grok (`grok -p` Composer 2.5)      | Pi model chain | Gemini via Antigravity CLI    | DEGRADED: host self-review    |
| `codex`       | Claude (`claude -p` Opus xhigh) | Grok (`grok -p` Composer 2.5) | Pi model chain | Gemini via Antigravity CLI       | DEGRADED: host self-review    |
| `grok`        | Codex (`codex exec`)       | Claude (`claude -p` Opus xhigh)    | Pi model chain | Gemini via Antigravity CLI       | DEGRADED: host self-review    |
| `pi`          | Codex (`codex exec`)       | Claude (`claude -p` Opus xhigh)    | Grok (`grok -p` Composer 2.5) | Gemini via Antigravity CLI         | DEGRADED: host self-review    |
| `unknown`     | Grok (`grok -p` Composer 2.5) | Pi model chain | none                          | Gemini via Antigravity CLI                | DEGRADED: host self-review    |

The official `openai/codex-plugin-cc` plugin (slash command
`/codex:adversarial-review`) is **not** required. We invoke `codex exec`
directly so the skill works regardless of whether the official plugin is
installed.

## Detection: primary partner

### Codex (when host=claude)
```bash
which codex && test -f ~/.codex/auth.json && echo "CODEX_OK"
```
Run `codex login` once on a fresh machine. For ChatGPT-account auth, ensure
`forced_login_method = "chatgpt"` is set in `~/.codex/config.toml` (see
[`codex-integration.md`](codex-integration.md)).

### Grok (when host=claude or host=codex, or first when host=unknown)
```bash
which grok && grok models
```
Uses headless Grok Build CLI with `grok-composer-2.5-fast` by default. See
[`grok-integration.md`](grok-integration.md).

### Pi (when earlier external paths fail)
```bash
which pi && pi --version
```
Uses headless Pi with this default model chain:

```bash
default
opencode-go/glm-5.2:high
moonshotai/kimi-k2.7-code-highspeed
```

`default` means Pi is called without `--model`, so Pi's own configured provider,
model, and thinking level decide the first attempt. The Moonshot leg is direct
Moonshot API via Pi provider `moonshotai`; it is not OpenRouter.

See [`pi-integration.md`](pi-integration.md). The call must stay in the caller's
repo/worktree root on this machine because the opencode-go key can resolve
through Doppler's current-directory scope.

### Claude (when host=codex)
```bash
which claude
```
Auth is managed by the Claude desktop / `claude login` flow. `claude -p`
fails fast if not authenticated.

## Gemini via Antigravity CLI (used by all directions when earlier paths fail)

### Detection
```bash
command -v agy || test -x "$HOME/.local/bin/agy"
```

Antigravity owns Gemini auth and model selection. This plugin does not call the
standalone `gemini` CLI.

### Invocation
```bash
agy --print --print-timeout "${ADVERSARIAL_REVIEW_TIMEOUT:-300}s" --sandbox "$prompt"
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

Operational logs are appended to `/tmp/call-external-codex.err`,
`/tmp/call-external-claude.err`, `/tmp/call-external-grok.err`,
`/tmp/call-external-pi.err`, and `/tmp/call-external-antigravity.err`. Delete
to rotate. The script does not auto-rotate; persistence by design.

## What this chain does NOT do

- **No Anthropic API key auth path.** Claude side uses the OAuth-managed CLI.
  If you have only an `ANTHROPIC_API_KEY`, `claude` CLI handles it
  transparently. No special handling here.
- **No OpenAI API key auth for Codex.** Codex CLI handles `OPENAI_API_KEY`
  vs ChatGPT subscription internally; we just call `codex exec`.
- **No retry on the same model.** If Codex stalls, we continue the fallback
  chain. Codex stalls (rare; verified) suggest backend issue, not transient. Retry is
  unlikely to help in the timeout we have.
