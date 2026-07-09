# Grok Build CLI integration

`lib/call-external.sh` can route adversarial reviews through **Grok Build CLI**
using `grok-4.5` with `--reasoning-effort xhigh` by default.

## When Grok is used

| Detected host | Grok role |
|---------------|-----------|
| `claude` | Secondary partner after Codex fails |
| `codex` | Tertiary fallback after Pi and Claude fail |
| `grok` | Never called as external (would violate cross-host principle) |
| `unknown` | First partner tried before Pi and Antigravity |

## Detection

`lib/detect-host.sh` returns `grok` when any of these are set:

- `GROK_HOME`
- `GROK_LOG_FILE`
- `GROK_AGENT_SECRET`

Or when the process tree contains a `grok` / `grok-build` ancestor.

## Invocation

```bash
grok -p "$prompt" \
  -m "${ADVERSARIAL_REVIEW_GROK_MODEL:-grok-4.5}" \
  --reasoning-effort "${ADVERSARIAL_REVIEW_GROK_EFFORT:-xhigh}" \
  --yolo \
  --output-format plain \
  --no-auto-update \
  --cwd "${PWD}"
```

Headless Grok can inherit `~/.grok/config.toml` `[models] default`, but the script
still passes `-m` and `--reasoning-effort` explicitly so external calls stay pinned
to Grok 4.5 xhigh even if the interactive default changes later.

## Auth

Preferred local auth is `XAI_API_KEY` or the same session auth as interactive Grok Build CLI. `grok models` should list `grok-4.5`, so the Grok leg uses direct Grok CLI auth, not OpenRouter and not Pi's `xai-oauth` provider.

Do not write the xAI key into this repo. Keep it in the process environment,
Doppler, shell secret management, or Grok's own auth store.

If headless calls fail with `Auth(AuthorizationRequired)`, first confirm the key
path:

```bash
grok models
```

The output should list `grok-4.5`. If auth is missing, restore `XAI_API_KEY` or run `grok login` once in an interactive session, then retry.

## Recommended Grok config

```toml
# ~/.grok/config.toml
[models]
default = "grok-4.5"
```

## Env vars

| Variable | Default | Effect |
|----------|---------|--------|
| `ADVERSARIAL_REVIEW_GROK_MODEL` | `grok-4.5` | Model id passed to `grok -m` |
| `ADVERSARIAL_REVIEW_GROK_EFFORT` | `xhigh` | Reasoning effort passed to `grok --reasoning-effort`. Set it empty to omit the flag |
| `XAI_API_KEY` | inherited from environment | Preferred Grok CLI auth for Grok 4.5 |
| `ADVERSARIAL_REVIEW_TIMEOUT` | `300` | Wall-clock cap when `timeout(1)` exists |

On macOS, GNU `timeout` is often missing. The script falls back to running
without a wall-clock cap and logs `WARN: timeout(1) not found`.

## Verification

```bash
# Non-spending auth/model preflight
grok models
# stdout should list: grok-4.5

# Grok as external (unknown host forces grok-first path)
printf '%s\n' 'Reply with exactly: EXTERNAL_OK' \
  | ADVERSARIAL_REVIEW_HOST=unknown \
    bash lib/call-external.sh 2>/tmp/call-external-grok.err
# stderr should include: calling: grok -p -m grok-4.5 --reasoning-effort xhigh

# Grok host routes away from itself
printf '%s\n' 'Reply EXTERNAL_OK' \
  | ADVERSARIAL_REVIEW_HOST=grok \
    bash lib/call-external.sh 2>/tmp/call-external-grok-host.err
# stderr should try codex/claude, never grok
```

## Logs

Grok stderr is appended to `/tmp/call-external-grok.err`.
