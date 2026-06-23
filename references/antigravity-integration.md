# Antigravity Gemini integration

`lib/call-external.sh` uses Antigravity CLI for the Gemini fallback. It must not
call the standalone `gemini` CLI for adversarial-review fallback work.

## When Antigravity is used

Antigravity is the final external fallback after the host-specific partner,
Grok, and Pi/opencode-go paths fail.

| Detected host | Antigravity role |
|---------------|------------------|
| `claude` | Fallback after Codex, Grok, and Pi fail |
| `codex` | Fallback after Claude, Grok, and Pi fail |
| `grok` | Fallback after Codex, Claude, and Pi fail |
| `pi` | Fallback after Codex, Claude, and Grok fail |
| `unknown` | Fallback after Grok and Pi fail |

## Invocation

Default command discovery checks `ADVERSARIAL_REVIEW_ANTIGRAVITY_CMD`, then
`agy` on `PATH`, then `$HOME/.local/bin/agy`, then `antigravity` on `PATH`.

```bash
agy \
  --print \
  --print-timeout "${ADVERSARIAL_REVIEW_TIMEOUT:-300}s" \
  --sandbox \
  "$prompt"
```

Use `--print` for non-interactive mode. Use `--sandbox` so the fallback remains
a review-only path. Antigravity owns Gemini auth and model selection through the
Antigravity app/session.

## Env vars

| Variable | Default | Effect |
|----------|---------|--------|
| `ADVERSARIAL_REVIEW_ANTIGRAVITY_CMD` | `agy` discovery | CLI command or absolute path |
| `ADVERSARIAL_REVIEW_TIMEOUT` | `300` | Passed to both wrapper timeout and `--print-timeout` |

## Verification

```bash
agy --version
agy --help
```

For a live smoke test, run from a trusted repo/worktree and keep the prompt
short:

```bash
printf '%s\n' 'Reply with exactly: ANTIGRAVITY_OK' \
  | ADVERSARIAL_REVIEW_HOST=unknown \
    ADVERSARIAL_REVIEW_GROK_MODEL=missing-model \
    ADVERSARIAL_REVIEW_PI_MODELS=missing-model \
    bash lib/call-external.sh
```

## Logs

Antigravity stderr is appended to `/tmp/call-external-antigravity.err`.
