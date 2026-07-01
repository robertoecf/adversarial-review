# Host detection

`lib/detect-host.sh` outputs exactly one of `claude`, `codex`, `grok`, `pi`, or `unknown`
on stdout, exit `0` on success, exit `1` on `unknown`.

## Why this matters - the cross-host principle

The whole point of this plugin is **the partner reviews, never the host**.
Detection is what makes that work without manual configuration. If detection
returns the wrong answer, the skill ends up self-reviewing - a silent failure
mode the principle was designed to forbid.

## Detection priority (top wins)

1. **`ADVERSARIAL_REVIEW_HOST` env override** - explicit user/test override.
   Always wins. Useful for sandboxes, weird wrappers, future hosts, and
   scripted tests.
2. **Grok Build CLI env markers** - `GROK_HOME`, `GROK_LOG_FILE`, or
   `GROK_AGENT_SECRET` set.
3. **Codex env markers** - `CODEX_THREAD_ID` or `CODEX_CI` set. These are set
   *only* by Codex and do **not** leak into nested processes that Codex
   launches from elsewhere.
4. **Pi env marker**: `PI_CODING_AGENT` set. Checked after Codex so a Codex
   child launched by Pi still detects as Codex.
5. **Claude Code env markers** - `CLAUDE_CODE_ENTRYPOINT` or
   `CLAUDE_AGENT_SDK_VERSION` set. ⚠️ These **do** leak into nested Codex
   processes when Codex is launched by Claude (verified empirically). That's
   why Codex env is checked before Claude env.
6. **Process-tree walk**: walk PPIDs up to 8 levels, return on first ancestor
   whose `comm` matches `grok` / `grok-build`, `codex` / `codex-cli`, or
   `claude` / `claude-code`, or `pi`. Innermost host wins.
7. If all fail → output `unknown`, exit `1`.

## Why this order

- **Override first** so a user can always force the answer regardless of bugs
  in auto-detection.
- **Codex env before Claude env** specifically because of env-leak asymmetry:
  Claude vars leak into nested Codex; Codex vars do not leak from nested into
  parent. Checking Codex first wins in the leak case.
- **Process tree last** because it's relatively expensive (one `ps` call per
  ancestor). Env checks are zero-fork.

## Anti-recursion chain

`lib/call-external.sh` reads `ADVERSARIAL_REVIEW_DEPTH` (default `0`). If
≥ `1`, it refuses with exit `1`. Before invoking the partner, it sets
`ADVERSARIAL_REVIEW_DEPTH=1` in the partner's env. So:

```
[claude host, DEPTH=0]
  → call-external.sh  (host=claude, partner=codex)
    → codex exec  with env ADVERSARIAL_REVIEW_DEPTH=1
      → if codex tries to invoke this skill again
        → call-external.sh sees DEPTH=1, refuses, exit 1
```

This prevents infinite ping-pong if a prompt accidentally re-triggers
review on the partner side.

## Override env vars

| Variable                              | Effect                                                                    |
|---------------------------------------|---------------------------------------------------------------------------|
| `ADVERSARIAL_REVIEW_HOST`             | Force host to `claude` / `codex` / `grok` / `pi` / `unknown`. Skips all auto-detection. |
| `ADVERSARIAL_REVIEW_DEPTH`            | Anti-recursion counter (default 0). Set >= 1 to disable cross-host review. |
| `ADVERSARIAL_REVIEW_FORCE_DEGRADED`   | If `1`, skip externals entirely; emit degraded banner. Smoke-test helper. |
| `ADVERSARIAL_REVIEW_TIMEOUT`          | Seconds for the partner call (default 300).                               |
| `ADVERSARIAL_REVIEW_GROK_MODEL`       | Grok Build CLI model id (default `grok-composer-2.5-fast`).               |
| `ADVERSARIAL_REVIEW_PI_MODELS`        | Comma-separated Pi model chain.                               |
| `ADVERSARIAL_REVIEW_PI_MODEL`         | Back-compat single Pi model id override.                                  |
| `ADVERSARIAL_REVIEW_ANTIGRAVITY_CMD`  | Antigravity CLI command or absolute path.                                 |

## Verification

```bash
# In Claude Code:
bash lib/detect-host.sh   # → "claude"

# From inside `codex exec`:
codex exec --sandbox read-only --skip-git-repo-check \
  "bash $PWD/lib/detect-host.sh"   # → "codex"

# Override:
ADVERSARIAL_REVIEW_HOST=codex bash lib/detect-host.sh   # → "codex"

# Anti-recursion:
echo "x" | ADVERSARIAL_REVIEW_DEPTH=1 bash lib/call-external.sh
# → exit 1, stderr "recursion detected"

# Forced degraded (non-destructive):
echo "x" | ADVERSARIAL_REVIEW_FORCE_DEGRADED=1 bash lib/call-external.sh
# → exit 2, stdout starts with "⚠️  DEGRADED MODE"
```

## Edge cases

- **Sandboxed processes that hide PPID**: the walk fails (`ps` returns empty).
  The script falls through to `unknown`. Set `ADVERSARIAL_REVIEW_HOST` manually.
- **Future hosts** (e.g. hypothetical "Hermes Code"): unknown by default,
  override or extend the script.
- **macOS `ps` truncation**: `comm` is limited to 15 chars on some kernels.
  `claude` and `codex` fit; `claude-code` and `codex-cli` also fit; longer
  names would need `ps -o args= -p $pid` instead.
