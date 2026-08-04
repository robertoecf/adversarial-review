# Direct xAI integration through Grok CLI

`lib/call-external.sh` routes direct-xAI adversarial reviews through Grok CLI.
The default model chain contains only `grok-4.5`, with
`--reasoning-effort high`. Grok 4.5 is xAI's frontier model.

The Composer 2.5 preference introduced 2026-07-21 was revoked on 2026-07-23
because Grok 4.5 is xAI's frontier model.

Before a review, the script runs `grok models`. It skips a configured model
that is absent from the live catalog. The environment overrides and multi-model
chain remain available for explicit caller configuration.

## When direct xAI is used

| Detected host | Direct-xAI role |
|---------------|------------------|
| `claude` | Primary partner for code/diff reviews, secondary after Codex for plan reviews |
| `codex` | Fallback after Pi and Claude fail |
| `grok` | Never called as external, because that would violate the cross-host principle |
| `pi` | Fallback after Codex and Claude fail |
| `unknown` | First partner tried before Pi and Antigravity |

## Invocation

The canonical direct-xAI invocation is:

```bash
grok -p "<prompt>" -m grok-4.5 --reasoning-effort high < /dev/null
```

The script also supplies its non-interactive output, update, and
working-directory flags. It captures candidate stdout and emits it only after a successful call,
so a failed model does not contaminate the next model's review.

## Auth and current availability

Preferred local auth is inherited `XAI_API_KEY` or the same direct xAI auth as
interactive Grok CLI. This route is not OpenRouter and is distinct from Pi's
`xai-oauth` provider.

Model availability is account and date dependent. The script uses Grok 4.5 at
high, the highest tier accepted by the current Grok CLI, when the model is
listed in the live catalog.

Do not write the xAI key into this repo. Keep it in the process environment,
Doppler, shell secret management, or Grok's own auth store.

## Env vars

| Variable | Default | Effect |
|----------|---------|--------|
| `ADVERSARIAL_REVIEW_GROK_MODELS` | `grok-4.5` | Ordered direct-xAI model chain |
| `ADVERSARIAL_REVIEW_GROK_MODEL` | unset | Back-compat single-model override, used only when the plural variable is unset |
| `ADVERSARIAL_REVIEW_GROK_EFFORT` | `high` | Effort for all direct-xAI candidates |
| `XAI_API_KEY` | inherited | Preferred direct xAI auth |
| `ADVERSARIAL_REVIEW_TIMEOUT` | `300` | Wall-clock cap when `timeout(1)` exists |

## Verification

```bash
# Non-spending availability preflight
grok models

# Direct xAI as the first external path
printf '%s\n' 'Reply with exactly: EXTERNAL_OK' \
  | ADVERSARIAL_REVIEW_HOST=unknown \
    bash lib/call-external.sh 2>dispatch.err
```

Inspect stderr to confirm model availability and selection. An unavailable
configured model produces:

```text
direct-xAI model unavailable, skipping: grok-4.5
```

A selected default model produces:

```text
calling: grok -p -m grok-4.5 --reasoning-effort high
```

On macOS, GNU `timeout` is often missing. The script runs without a wrapper
wall-clock cap in that case and logs a warning.

## Logs

Grok stderr is appended to
`${XDG_STATE_HOME:-$HOME/.local/state}/adversarial-review/grok.err`.
