# adversarial-review

Cross-host adversarial review for coding workflows. Works in **both Claude
Code and Codex** from the same source - detects which agent host you're
running in and routes the heavy critique to the OTHER agent.

## The principle

> **The partner reviews, never the host.**

Two models examining the same artifact from different angles catch more
issues than either alone. Each has different training biases, blind spots,
and reasoning patterns. Disagreements between the two surface the
highest-value findings - the ones a single reviewer would miss.

This plugin enforces that principle automatically:

- Running in **Claude Code** -> external reviewer is **Codex** (`codex exec`,
  `gpt-5.4 xhigh` via ChatGPT subscription auth)
- Running in **Codex** -> external reviewer is **Claude (Opus, xhigh)** via
  `claude -p`
- If the primary path fails, try Grok Build CLI, then Pi/opencode-go model chain
  (`opencode-go/glm-5.2:high`, `opencode-go/deepseek-v4-pro:xhigh`,
  `opencode-go/deepseek-v4-flash:xhigh`), then Gemini via non-interactive
  Antigravity CLI (`agy --print`)
- Everything unavailable -> **degraded mode** with explicit banner: the host
  reviews itself, but the user is told the cross-host principle was bypassed

## How it works

```
SKILL.md (same file in both hosts)
   │
   ├─ host runs lib/call-external.sh
   │     │
   │     ├─ lib/detect-host.sh  (override -> env -> PPID walk)
   │     ├─ partner = NOT host
   │     ├─ ADVERSARIAL_REVIEW_DEPTH = 1  (anti-recursion guard)
   │     ├─ try partner (codex exec OR claude -p)
   │     ├─ on fail -> grok, then pi/opencode-go
   │     ├─ on fail -> Gemini via Antigravity
   │     └─ on fail -> degraded mode (exit 2)
   │
   ├─ host runs its own independent analysis (no peeking at partner output)
   ├─ cross-validate: tag findings [cross-validated] / [external-only] / [host-only]
   └─ return unified output (P0-P3 severity, evidence, recommendation, partner-attribution)
```

No haiku courier subagent (removed in 0.5.0 - added complexity without value).
The main session does the dispatch and synthesis directly.

## Skills

| Skill                                             | What it does                                              |
|---------------------------------------------------|-----------------------------------------------------------|
| `/adversarial-review:adversarial-plan-review`     | Pre-implementation plan critique. Returns revised plan.  |
| `/adversarial-review:coding-adversarial-review`   | Red-team code/diff/config. Returns critics + patch.       |
| `/adversarial-review:prompt-optimize`             | Prompt-engineering analysis (single-host, no external).   |
| `/adversarial-review:review-all`                  | Classifies input and routes to the right skill above.     |

In Codex, after running the install script, the same skills are available
as `$<skill-name>` (Codex prompt-prefix convention).

## Install

### Claude Code

```bash
# Add the marketplace and install the plugin
claude plugin marketplace add ~/repos/coding-plugins/adversarial-review
claude plugin install adversarial-review@adversarial-review

# Reload in current session
/reload-plugins
```

### Codex (additionally)

```bash
# Symlinks each skills/<name>/ into ~/.codex/skills/
bash ~/repos/coding-plugins/adversarial-review/adapters/codex-skill/install.sh
```

Verify both:

```bash
claude plugin list                 # should show adversarial-review enabled
ls -la ~/.codex/skills/            # should show 4 symlinks back to this repo
```

### Prerequisites

At least one external partner CLI must be authenticated for cross-host review
to work (otherwise you'll get DEGRADED mode):

```bash
# When host=claude, partner=codex:
codex login

# When host=codex, partner=claude:
claude  # interactive once to register OAuth, then `claude -p` works headless

# Optional fallback:
pi --version
grok --version
agy --version  # Antigravity CLI, authenticated through the Antigravity app
```

For ChatGPT-account Codex users, also add to `~/.codex/config.toml`:

```toml
forced_login_method = "chatgpt"
```

(Without this, `codex exec` returns 404 "Model not found" even though the
TUI works. See `references/codex-integration.md` for the gotcha details.)

## Verify

```bash
# Detection in Claude Code
bash ~/repos/coding-plugins/adversarial-review/lib/detect-host.sh
# -> claude

# Detection inside Codex
codex exec --sandbox read-only --skip-git-repo-check \
  "bash $HOME/repos/coding-plugins/adversarial-review/lib/detect-host.sh"
# -> codex

# Override
ADVERSARIAL_REVIEW_HOST=codex bash lib/detect-host.sh
# -> codex

# Degraded mode (non-destructive smoke)
echo "test" | ADVERSARIAL_REVIEW_FORCE_DEGRADED=1 \
  bash lib/call-external.sh
# -> exit 2, stdout begins with "⚠️  DEGRADED MODE"

# Anti-recursion
echo "test" | ADVERSARIAL_REVIEW_DEPTH=1 \
  bash lib/call-external.sh
# -> exit 1, stderr "recursion detected"
```

## Use

```bash
# In Claude Code
/adversarial-review:adversarial-plan-review            # paste plan or point to file
/adversarial-review:coding-adversarial-review          # paste code, point to file, or "review uncommitted"
/adversarial-review:prompt-optimize                    # paste a system prompt or skill definition
/adversarial-review:review-all                         # paste anything - auto-routes

# In Codex (after running adapters/codex-skill/install.sh)
$adversarial-plan-review please review the plan I'm about to implement: ...
$coding-adversarial-review review my changes: ...
```

## Architecture diagram

[![Architecture](https://excalidraw.com/og/5S7Pzstx9npv10zCbtwkV)](https://excalidraw.com/#json=5S7Pzstx9npv10zCbtwkV,AJzXgdXVwoc3ojldcMgGZA)

> [Open in Excalidraw](https://excalidraw.com/#json=5S7Pzstx9npv10zCbtwkV,AJzXgdXVwoc3ojldcMgGZA)

## See also

- `references/host-detection.md` - the override -> env -> PPID walk priority
- `references/codex-integration.md` - Codex CLI specifics + `forced_login_method` gotcha
- `references/claude-integration.md` - `claude -p --model opus --effort xhigh`
- `references/pi-integration.md` - Pi/opencode-go model chain
- `references/antigravity-integration.md` - Gemini through non-interactive Antigravity CLI
- `references/fallback-chain.md` - external chain + Antigravity + degraded path
- `AGENTS.md` - agent-side rules (severity, honesty, anti-recursion contract)
- `CLAUDE.md` - Claude Code dev workflow

## License

MIT
