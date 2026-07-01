# Pi model chain integration

`lib/call-external.sh` can route adversarial reviews through headless Pi using
this default chain:

1. `default`, Pi's configured default provider, model, and thinking level
2. `opencode-go/glm-5.2:high`
3. `moonshotai/kimi-k2.7-code-highspeed`, direct Moonshot API, not OpenRouter

`default` intentionally delegates to Pi settings. The Moonshot fallback uses the
Pi built-in provider id `moonshotai` and requires `MOONSHOT_API_KEY` in the
process environment or Pi auth storage.

## Official Moonshot facts

As of 2026-06-30, Kimi's official docs say:

- OpenAI-compatible base URL: `https://api.moonshot.ai/v1`
- API key header: `Authorization: Bearer $MOONSHOT_API_KEY`
- Direct model ids include `kimi-k2.7-code` and `kimi-k2.7-code-highspeed`
- `kimi-k2.7-code-highspeed` is the high-speed variant of the same model
- For `kimi-k2.7-code`, thinking is always on. Do not pass a disabled thinking
  parameter.

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
IFS=, read -r -a models <<< "${ADVERSARIAL_REVIEW_PI_MODELS:-default,opencode-go/glm-5.2:high,moonshotai/kimi-k2.7-code-highspeed}"
for model in "${models[@]}"; do
  if [ "$model" = "default" ]; then
    pi -p --mode text --no-tools "$prompt"
  else
    pi -p --mode text --no-tools --model "$model" "$prompt"
  fi
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

Moonshot direct does not use OpenRouter. It uses Pi's built-in `moonshotai`
provider, backed by `MOONSHOT_API_KEY`.

## Env vars

| Variable | Default | Effect |
|----------|---------|--------|
| `ADVERSARIAL_REVIEW_PI_MODELS` | `default,opencode-go/glm-5.2:high,moonshotai/kimi-k2.7-code-highspeed` | Comma-separated Pi model chain, tried in order. The token `default` calls Pi without `--model` |
| `ADVERSARIAL_REVIEW_PI_MODEL` | unset | Back-compat single model override, used only when `ADVERSARIAL_REVIEW_PI_MODELS` is unset. It may also be `default` |
| `MOONSHOT_API_KEY` | unset | Required by Pi for the direct `moonshotai/...` fallback |
| `ADVERSARIAL_REVIEW_TIMEOUT` | `300` | Wall-clock cap when `timeout(1)` exists |

## Model registry check

Useful discovery commands:

```bash
MOONSHOT_API_KEY=dummy pi --list-models moonshotai/kimi-k2.7-code-highspeed
pi --list-models k2.7
```

With no `MOONSHOT_API_KEY`, Pi may omit direct `moonshotai` models from
`--list-models`. That does not mean OpenRouter should be used. It means the
Moonshot direct key is not configured for that process.

## Verification

Use a short prompt from a repo/worktree with the right Doppler scope:

```bash
printf '%s\n' 'Reply with exactly: EXTERNAL_OK' \
  | ADVERSARIAL_REVIEW_HOST=unknown \
    ADVERSARIAL_REVIEW_GROK_MODEL=missing-model \
    bash lib/call-external.sh 2>/tmp/call-external-pi.err
```

The stderr log should include either `calling: pi -p --mode text --no-tools
(default config` or `calling: pi -p --mode text --no-tools --model`.

For one-off provider/model proof, run Pi separately with `--mode json` and
inspect the final `message_end` metadata. Do not use JSON mode for routine long
reviews.

Useful model proof commands:

```bash
pi -p --mode text --no-tools 'Reply exactly: PI_DEFAULT_OK'

pi -p --mode text --no-tools --model opencode-go/glm-5.2:high \
  'Reply exactly: GLM_52_OK'

MOONSHOT_API_KEY=... pi -p --mode text --no-tools \
  --model moonshotai/kimi-k2.7-code-highspeed \
  'Reply exactly: MOONSHOT_KIMI_HIGHSPEED_OK'
```

## Logs

Pi stderr is appended to `/tmp/call-external-pi.err`.
