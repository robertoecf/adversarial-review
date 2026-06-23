# Grok Build CLI integration

`lib/call-external.sh` can route adversarial reviews through **Grok Build CLI**
using the first-party Composer 2.5 model (`grok-composer-2.5-fast` by default).

## When Grok is used

| Detected host | Grok role |
|---------------|-----------|
| `claude` | Secondary partner after Codex fails |
| `codex` | Secondary partner after Claude fails |
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
  -m "${ADVERSARIAL_REVIEW_GROK_MODEL:-grok-composer-2.5-fast}" \
  --yolo \
  --output-format plain \
  --no-auto-update \
  --cwd "${PWD}"
```

Headless Grok inherits `~/.grok/config.toml` `[models] default`. The script
still passes `-m` explicitly so external calls stay pinned to Composer 2.5 even
if the interactive default changes later.

## Auth

Grok uses the same session auth as interactive Grok Build CLI (`grok login` or
`~/.grok/auth.json`). No separate Cursor subscription is required - xAI proxies
Composer 2.5 through `cli-chat-proxy.grok.com`.

If headless calls fail with `Auth(AuthorizationRequired)`, run `grok login` once
in an interactive session, then retry.

## Recommended Grok config

```toml
# ~/.grok/config.toml
[models]
default = "grok-composer-2.5-fast"
```

## Env vars

| Variable | Default | Effect |
|----------|---------|--------|
| `ADVERSARIAL_REVIEW_GROK_MODEL` | `grok-composer-2.5-fast` | Model id passed to `grok -m` |
| `ADVERSARIAL_REVIEW_TIMEOUT` | `300` | Wall-clock cap when `timeout(1)` exists |

On macOS, GNU `timeout` is often missing. The script falls back to running
without a wall-clock cap and logs `WARN: timeout(1) not found`.

## Verification

```bash
# Grok as external (unknown host forces grok-first path)
printf '%s\n' 'Reply with exactly: EXTERNAL_OK' \
  | ADVERSARIAL_REVIEW_HOST=unknown \
    bash lib/call-external.sh 2>/tmp/call-external-grok.err
# stderr should include: calling: grok -p -m grok-composer-2.5-fast

# Grok host routes away from itself
printf '%s\n' 'Reply EXTERNAL_OK' \
  | ADVERSARIAL_REVIEW_HOST=grok \
    bash lib/call-external.sh 2>/tmp/call-external-grok-host.err
# stderr should try codex/claude, never grok
```

## Logs

Grok stderr is appended to `/tmp/call-external-grok.err`.
