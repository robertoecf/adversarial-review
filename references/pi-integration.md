# Pi/opencode-go model chain integration

`lib/call-external.sh` can route adversarial reviews through headless Pi using
this default model chain:

1. `opencode-go/glm-5.2:high`
2. `opencode-go/deepseek-v4-pro:xhigh`
3. `opencode-go/deepseek-v4-flash:xhigh`

For the DeepSeek models, Pi maps `xhigh` to the provider's max thinking level
through `~/.pi/agent/models.json`.

## When Pi is used

| Detected host | Pi role |
|---------------|---------|
| `claude` | Fallback after Codex and Grok fail |
| `codex` | Fallback after Claude and Grok fail |
| `grok` | Fallback after Codex and Claude fail |
| `pi` | Never called as external, because that would self-review |
| `unknown` | Fallback after Grok fails |

## Invocation

```bash
IFS=, read -r -a models <<< "${ADVERSARIAL_REVIEW_PI_MODELS:-opencode-go/glm-5.2:high,opencode-go/deepseek-v4-pro:xhigh,opencode-go/deepseek-v4-flash:xhigh}"
for model in "${models[@]}"; do
  pi -p --mode text --no-tools --model "$model" "$prompt"
done
```

Use `--mode text` for normal review. `--mode json` can re-emit the full
cumulative assistant message on every update and produce huge output files on
long reviews.

Use `--no-tools` for pure critique. The reviewer should not mutate files or run
a tool loop during an external adversarial pass.

## Current-directory requirement

Keep the call in the caller's repo or worktree root. On this machine the
opencode-go key can be stored in `~/.pi/agent/auth.json` as a Doppler reference:

```text
!doppler secrets get OPENCODE_GO_API_KEY --plain
```

Doppler resolves project scope from the current directory. Running Pi from
`/tmp` or another scopeless directory can surface as "No API key for provider:
opencode-go" or appear to hang. `call-external.sh` therefore does not `cd` into
the plugin directory before invoking Pi.

## Env vars

| Variable | Default | Effect |
|----------|---------|--------|
| `ADVERSARIAL_REVIEW_PI_MODELS` | `opencode-go/glm-5.2:high,opencode-go/deepseek-v4-pro:xhigh,opencode-go/deepseek-v4-flash:xhigh` | Comma-separated model chain passed to `pi --model`, tried in order |
| `ADVERSARIAL_REVIEW_PI_MODEL` | unset | Back-compat single model override, used only when `ADVERSARIAL_REVIEW_PI_MODELS` is unset |
| `ADVERSARIAL_REVIEW_TIMEOUT` | `300` | Wall-clock cap when `timeout(1)` exists |

## Verification

Use a short prompt from a repo/worktree with the right Doppler scope:

```bash
printf '%s\n' 'Reply with exactly: EXTERNAL_OK' \
  | ADVERSARIAL_REVIEW_HOST=unknown \
    ADVERSARIAL_REVIEW_GROK_MODEL=missing-model \
    bash lib/call-external.sh 2>/tmp/call-external-pi.err
```

The stderr log should include `calling: pi -p --mode text --no-tools --model`.

For one-off provider/model proof, run Pi separately with `--mode json` and
inspect the final `message_end` metadata. Do not use JSON mode for routine long
reviews.

Useful model proof commands:

```bash
pi -p --mode text --no-tools --model opencode-go/deepseek-v4-pro:xhigh \
  'Reply exactly: DEEPSEEK_PRO_OK'

pi -p --mode text --no-tools --model opencode-go/deepseek-v4-flash:xhigh \
  'Reply exactly: DEEPSEEK_FLASH_OK'
```

## Logs

Pi stderr is appended to `/tmp/call-external-pi.err`.
