# Pi model chain integration

`lib/call-external.sh` can route adversarial reviews through headless Pi using
this default chain:

1. `xai-oauth/grok-4.5` with `--thinking xhigh`
2. `opencode-go/glm-5.2:high`
3. `moonshotai/kimi-k3:xhigh`, direct Moonshot API, not OpenRouter

The first leg intentionally uses Pi's xAI OAuth provider with Grok 4.5 and
xhigh thinking. The Moonshot fallback uses the Pi built-in provider id
`moonshotai`, model `kimi-k3`, xhigh thinking, and requires `MOONSHOT_API_KEY`
in the process environment or Pi auth storage. The token
`default` remains supported as an explicit override when the caller wants Pi's
configured default provider, model, and thinking level.

## Moonshot availability evidence

As of 2026-07-21, `pi --list-models moonshotai` lists `moonshotai/kimi-k3`
with thinking support and a 1M context window. A direct non-interactive smoke
returned provider `moonshotai`, model `kimi-k3`, and thinking content.

The direct provider uses `MOONSHOT_API_KEY`. Do not place that key in this repo
or in review prompts.

## When Pi is used

| Detected host | Pi role |
|---------------|---------|
| `claude` | Fallback after Codex and Grok fail |
| `codex` | Primary external reviewer. Runs before Claude and Grok |
| `grok` | Non-xAI fallback after Codex and Claude fail. GLM then Kimi, never Grok |
| `pi` | Never called as external, because that would self-review |
| `unknown` | Fallback after Grok fails |

## Invocation

```bash
IFS=, read -r -a models <<< "${ADVERSARIAL_REVIEW_PI_MODELS:-xai-oauth/grok-4.5,opencode-go/glm-5.2:high,moonshotai/kimi-k3:xhigh}"
pi_thinking="${ADVERSARIAL_REVIEW_PI_THINKING:-xhigh}"
for model in "${models[@]}"; do
  if [ "$model" = "default" ]; then
    pi -p --mode text --no-tools --no-session "$prompt"
  elif [[ "$model" =~ :(off|minimal|low|medium|high|xhigh)$ ]]; then
    pi -p --mode text --no-tools --no-session --model "$model" "$prompt"
  elif [ "$model" = "${models[0]}" ] && [ -n "$pi_thinking" ]; then
    pi -p --mode text --no-tools --no-session --model "$model" --thinking "$pi_thinking" "$prompt"
  else
    pi -p --mode text --no-tools --no-session --model "$model" "$prompt"
  fi
done
```

Use `--mode text` for normal review. `--mode json` can re-emit the full
cumulative assistant message on every update and produce huge output files on
long reviews.

Use `--no-tools` for pure critique and `--no-session` so external review smoke tests do not persist Pi sessions. The reviewer should not mutate files or run
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
| `ADVERSARIAL_REVIEW_PI_MODELS` | `xai-oauth/grok-4.5,opencode-go/glm-5.2:high,moonshotai/kimi-k3:xhigh` | Comma-separated Pi model chain, tried in order. The token `default` calls Pi without `--model` |
| `ADVERSARIAL_REVIEW_PI_THINKING` | `xhigh` | Pi `--thinking` level for the first explicit model token without a `:level` suffix. Set it empty to omit `--thinking` |
| `ADVERSARIAL_REVIEW_PI_MODEL` | unset | Back-compat single model override, used only when `ADVERSARIAL_REVIEW_PI_MODELS` is unset. It may also be `default` |
| `MOONSHOT_API_KEY` | unset | Required by Pi for the direct `moonshotai/...` fallback |
| `ADVERSARIAL_REVIEW_TIMEOUT` | `300` | Wall-clock cap when `timeout(1)` exists |

## Model registry check

Useful discovery commands:

```bash
pi --list-models moonshotai
pi --list-models kimi-k3
```

With no `MOONSHOT_API_KEY`, Pi may omit direct `moonshotai` models from
`--list-models`. That does not mean OpenRouter should be used. It means the
Moonshot direct key is not configured for that process.

## Verification

Use a short prompt from a repo/worktree with the right Doppler scope:

```bash
printf '%s\n' 'Reply with exactly: EXTERNAL_OK' \
  | ADVERSARIAL_REVIEW_HOST=unknown \
    ADVERSARIAL_REVIEW_GROK_MODELS=missing-model \
    bash lib/call-external.sh 2>dispatch.err
```

The stderr log should include either `calling: pi -p --mode text --no-tools --no-session
--model xai-oauth/grok-4.5 --thinking xhigh` or another explicit Pi model from the
configured chain.

For one-off provider/model proof, run Pi separately with `--mode json` and
inspect the final `message_end` metadata. Do not use JSON mode for routine long
reviews.

Useful model proof commands:

```bash
pi -p --mode text --no-tools --no-session --model xai-oauth/grok-4.5 --thinking xhigh \
  'Reply exactly: PI_GROK_45_XHIGH_OK'

pi -p --mode text --no-tools --no-session --model opencode-go/glm-5.2:high \
  'Reply exactly: GLM_52_OK'

MOONSHOT_API_KEY=... pi -p --mode text --no-tools --no-session \
  --model moonshotai/kimi-k3 --thinking xhigh \
  'Reply exactly: MOONSHOT_KIMI_K3_OK'
```

## Logs

Pi stderr is appended to
`${XDG_STATE_HOME:-$HOME/.local/state}/adversarial-review/pi.err`.
