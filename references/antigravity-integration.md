# Antigravity multi-provider integration

`lib/call-external.sh` uses non-interactive Antigravity CLI as the final
external fallback. It uses the verified Gemini model IDs and never calls the standalone `gemini` CLI.

## Selection policy

The script runs `agy models`, keeps only currently listed candidates, and
tries this ladder:

1. `gemini-3.8-flash-high`
2. `gemini-3.7-flash-high`
3. `gemini-3.1-pro-high`


Availability has two gates:

1. Catalog availability, the exact model id must appear in `agy models`.
2. Usable quota, the actual non-interactive call must succeed.

If a listed model fails because its provider quota is exhausted or the call is
otherwise unavailable, the script advances to the next model. Candidate
stdout is emitted only on success.

## When Antigravity is used

Antigravity follows the primary route. For OpenAI-authored work after the two
Grok transports fail, and for Grok-authored work or host Grok after Codex fails,
it is the immediate fallback.

| Detected host | Antigravity role |
|---------------|------------------|
| `claude` | Fallback after Codex, direct xAI, and Pi fail |
| `codex` | Immediate after the applicable Grok or Codex primary route fails |
| `grok` | Immediate after Codex fails |
| `pi` | Fallback after Codex, Claude, and direct xAI fail |
| `unknown` | Fallback after direct xAI and Pi fail |

## Invocation

Default command discovery checks `ADVERSARIAL_REVIEW_ANTIGRAVITY_CMD`, then
`agy` on `PATH`, then `$HOME/.local/bin/agy`, then `antigravity` on `PATH`.

For each available candidate, the script invokes:

```bash
agy \
  -p "$prompt" \
  --print-timeout "${ADVERSARIAL_REVIEW_TIMEOUT:-300}s" \
  --model "$model" \
  --sandbox \
  --mode plan
```

`-p "$prompt"` makes the call a one-shot. Keep the prompt immediately after
`-p`, because Antigravity parses the next token as the prompt. `--sandbox` and
`--mode plan` together carry the review-only intent. Sandbox alone is not a
read-only guarantee. Never use `-c` or continue. Model IDs encode effort.

## Env vars

| Variable | Default | Effect |
|----------|---------|--------|
| `ADVERSARIAL_REVIEW_ANTIGRAVITY_CMD` | `agy` discovery | CLI command or absolute path |
| `ADVERSARIAL_REVIEW_ANTIGRAVITY_MODELS` | Gemini ladder above | Comma-separated ordered model ids |
| `ADVERSARIAL_REVIEW_TIMEOUT` | `300` | Passed to both wrapper timeout and `--print-timeout` |

## Verification

```bash
agy --version
agy models
```

For a live smoke test, force earlier legs to unavailable model ids and keep the
prompt short:

```bash
printf '%s\n' 'Reply with exactly: ANTIGRAVITY_OK' \
  | ADVERSARIAL_REVIEW_HOST=unknown \
    ADVERSARIAL_REVIEW_GROK_MODELS=missing-model \
    ADVERSARIAL_REVIEW_PI_MODELS=missing-model \
    bash lib/call-external.sh
```

## Logs

Antigravity stderr is appended to
`${XDG_STATE_HOME:-$HOME/.local/state}/adversarial-review/antigravity.err`.
