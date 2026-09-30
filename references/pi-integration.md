# Pi model chain integration

`lib/call-external.sh` can route adversarial reviews through headless Pi using
this default T2 chain (roster as of 2026-09-28, see the SKILL.md roster table):

1. `opencode-go/deepseek-v4.1-flash:xhigh`
2. `opencode-go/glm-5.3:high`
3. `xai-oauth/grok-4.7:high` (xhigh timed out at 400 to 540 s on 20 KB prompts)

Every Pi call runs with read-only tools (`--tools read,grep,find,ls`) from the
caller's repo or worktree root, so the reviewer can verify claims against the
checkout. The token `default` remains supported as an explicit override when
the caller wants Pi's configured default provider, model, and thinking level.

## OpenCode Go data residency

OpenCode Go deployments of DeepSeek may be hosted in China and require explicit
workspace opt-in. Without it, Pi text mode exits nonzero with a `RegionError`;
the dispatcher logs the failed attempt and continues down the chain. Treat the
opt-in as a separate data-residency decision, not as part of plugin installation.

## When Pi is used

| Detected host | Pi role |
|---------------|---------|
| `claude` | Fallback after Codex and Grok fail |
| `codex` | Pi Grok is primary for Codex/user/unknown authors. Claude/Pi authors retain the longer route. Grok authors never use Pi |
| `grok` | Never called. Codex falls directly to Gemini |
| `pi` | Never called as external, because that would self-review |
| `unknown` | Fallback after Grok fails |

## Invocation

```bash
tools=(--tools read,grep,find,ls)
lean=(--no-skills --no-prompt-templates --no-context-files)
IFS=, read -r -a models <<< "${ADVERSARIAL_REVIEW_PI_MODELS:-opencode-go/deepseek-v4.1-flash:xhigh,opencode-go/glm-5.3:high,xai-oauth/grok-4.7:high}"
for model in "${models[@]}"; do
  pi -p --mode text "${tools[@]}" --no-session "${lean[@]}" --model "$model" "$prompt"
done
```

Use `--mode text` for normal review. `--mode json` can re-emit the full
cumulative assistant message on every update and produce huge output files on
long reviews.

Reviewers get read-only tools so they can check claims against the checkout
(files, links, callers). No `bash`, `edit` or `write`: the reviewer never
mutates files, runs commands or reaches the network. `--no-session` keeps
review runs out of Pi's session store.

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
| `ADVERSARIAL_REVIEW_PI_MODELS` | `opencode-go/deepseek-v4.1-flash:xhigh,opencode-go/glm-5.3:high,xai-oauth/grok-4.7:high` | Comma-separated Pi model chain, tried in order. The token `default` calls Pi without `--model` |
| `ADVERSARIAL_REVIEW_PI_THINKING` | `xhigh` | Pi `--thinking` level for the first explicit model token without a `:level` suffix. Set it empty to omit `--thinking` |
| `ADVERSARIAL_REVIEW_PI_MODEL` | unset | Back-compat single model override, used only when `ADVERSARIAL_REVIEW_PI_MODELS` is unset. It may also be `default` |
| `ADVERSARIAL_REVIEW_TIMEOUT` | `300` | Wall-clock cap when `timeout(1)` exists |

## Model registry check

```bash
pi --list-models opencode-go
pi --list-models xai-oauth
pi --list-models openai-codex
```

## Verification

Use a short prompt from a repo/worktree with the right Doppler scope:

```bash
printf '%s\n' 'Reply with exactly: EXTERNAL_OK' \
  | ADVERSARIAL_REVIEW_HOST=unknown \
    ADVERSARIAL_REVIEW_GROK_MODELS=missing-model \
    bash lib/call-external.sh 2>dispatch.err
```

The stderr log should include `calling: pi -p --mode text --tools read,grep,find,ls
--no-session --model <model>` for a model from the configured chain.

For one-off provider/model proof, run Pi separately with `--mode json` and
inspect the final `message_end` metadata. Do not use JSON mode for routine long
reviews.

Useful model proof command (repeat per roster entry):

```bash
pi -p --mode text --tools read,grep,find,ls --no-session --no-skills --no-prompt-templates --no-context-files \
  --model opencode-go/deepseek-v4.1-flash:xhigh 'Reply exactly: PI_REVIEWER_OK'
```

## Logs

Pi stderr is appended to
`${XDG_STATE_HOME:-$HOME/.local/state}/adversarial-review/pi.err`.
