# adversarial-review

**v0.9.8**: Cross-host adversarial review for coding workflows. Works in
**Claude Code, Codex, Pi, and Grok** from the same source: detects which agent
host you're running in and routes the heavy critique to the OTHER agent.

Critique discipline (v0.8.1): break confidence rather than validate; expensive
attack surfaces first; material-only findings; mandatory simplicity
counterfactuals; steerable focus; terse ship/no-ship summary. Lessons adapted
from OpenAI Codex Companion and Matt Pocock's engineering skills.

Routing uses three tiers: T1 Claude and Codex review each other, T2 is the
Pi chain (opencode-go DeepSeek V4.1 Flash, GLM 5.3, then Grok 4.7), and T3 is
the Gemini Antigravity ladder as last resort. Reviewers get read-only tools.
On host Claude, Codex-authored work is reviewed by the Claude main loop itself.
Outside host Claude the Codex reviewer defaults to GPT-6 Astra medium; the
architect selects high only for auth, sensitive data, migrations, concurrency,
or changes spanning multiple modules. The Gemini ladder is `gemini-3.8-flash-high`,
`gemini-3.7-flash-high`, then `gemini-3.1-pro-high`.


## Simplicity counterfactual

Every plan and code review now asks whether the same required behavior and
safety can be delivered with fewer concepts, layers, seams, entry points, or
configuration surfaces. It checks YAGNI, pass-through layers, hypothetical
adapters, duplicate ownership, and missed reuse of existing in-repo modules.

Effect is conditional, not a framework preference: when the repository already
has a canonical Effect implementation for the concern, the reviewer challenges
a parallel implementation. It does not recommend introducing Effect merely to
reduce line count or enforce framework consistency. Fewer lines are a clue,
never the verdict.

## The principle

> **The partner reviews, never the host.**

Two models examining the same artifact from different angles catch more
issues than either alone. Each has different training biases, blind spots,
and reasoning patterns. Disagreements between the two surface the
highest-value findings - the ones a single reviewer would miss.

This plugin enforces that principle automatically:

- Running in **Claude Code** routes by author: Claude-authored work (default)
  uses Astra high via Pi first; Codex-authored work is reviewed inline by the
  Claude main loop, and the wrapper only adds T2/T3 opinions, never Codex.
- Running in **Codex** with a Codex, user, or unknown author uses `claude -p`
  first; Claude, Pi, or Grok authors use Codex Astra first. Then T2, then T3.
- Running in **Grok** uses Codex Astra, then Gemini.
- Codex Astra effort is medium by default. Set
  `ADVERSARIAL_REVIEW_CODEX_EFFORT=high` only for auth, sensitive data,
  migrations, concurrency, or changes spanning multiple modules.
- Antigravity is a one-shot review call with `-p`, `--sandbox`, and `--mode plan`.
- Everything unavailable enters **degraded mode** with an explicit banner.


## How it works

```
SKILL.md (same file in both hosts)
   │
   ├─ host runs lib/call-external.sh
   │     │
   │     ├─ lib/detect-host.sh  (override -> env -> PPID walk)
   │     ├─ partner = NOT host
   │     ├─ ADVERSARIAL_REVIEW_DEPTH = 1  (anti-recursion guard)
   │     ├─ select ordered partners from host + artifact + author
   │     ├─ try Codex, Claude, direct xAI, or Pi in that route's order
   │     ├─ on fail -> Gemini Antigravity ladder
   │     └─ on fail -> degraded mode (exit 2)
   │
   ├─ host runs its own independent analysis (no peeking at partner output)
   ├─ cross-validate: tag findings [cross-validated] / [external-only] / [host-only]
   └─ return unified output (P0-P3 severity, evidence, recommendation, partner-attribution)
```

No haiku courier subagent (removed in 0.5.0 - added complexity without value).
The main session does the dispatch and synthesis directly.

## Skills

| Skill                                             | What it does                                                            |
|---------------------------------------------------|--------------------------------------------------------------------------|
| `/adversarial-review:adversarial-review`          | Single entry point. Classifies input (plan, code, prompt) and runs the matching procedure: plan critique with revised plan, red-team code review with patch, or prompt-engineering analysis (external critique plus host adjudication). |

In Codex, after running the install script, the same skills are available
as `$<skill-name>` (Codex prompt-prefix convention).

## Install

### Claude Code

```bash
# Add the marketplace and install the plugin
claude plugin marketplace add ~/repos/skills/plugins/adversarial-review
claude plugin install adversarial-review@adversarial-review

# Reload in current session
/reload-plugins
```

### Codex (additionally)

```bash
# Symlinks each skills/<name>/ into ~/.codex/skills/
bash ~/repos/skills/plugins/adversarial-review/adapters/codex-skill/install.sh
```

Verify both:

```bash
claude plugin list                 # should show adversarial-review enabled
ls -la ~/.codex/skills/            # should show the adversarial-review symlink back to this repo
```

### Prerequisites

At least one external partner CLI must be authenticated for cross-host review
to work (otherwise you'll get DEGRADED mode):

```bash
# When host=claude, partner=codex:
codex login

# When host=codex and author=codex, partner=Pi xAI OAuth Grok 4.7 first:
pi --version

# Host=codex direct fallback after Pi:
grok --version

# Next host=codex fallback:
claude  # interactive once to register OAuth, then `claude -p` works headless

# Optional final fallback:
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
bash ~/repos/skills/plugins/adversarial-review/lib/detect-host.sh
# -> claude

# Detection inside Codex
codex exec --sandbox read-only --skip-git-repo-check \
  "bash $HOME/repos/skills/plugins/adversarial-review/lib/detect-host.sh"
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
/adversarial-review:adversarial-review                 # paste anything - plan, code, diff, prompt, or "review uncommitted"

# In Codex (after running adapters/codex-skill/install.sh)
$adversarial-review please review the plan I'm about to implement: ...
$adversarial-review review my changes: ...
```

## Architecture diagram

[![Architecture](https://excalidraw.com/og/5S7Pzstx9npv10zCbtwkV)](https://excalidraw.com/#json=5S7Pzstx9npv10zCbtwkV,AJzXgdXVwoc3ojldcMgGZA)

> [Open in Excalidraw](https://excalidraw.com/#json=5S7Pzstx9npv10zCbtwkV,AJzXgdXVwoc3ojldcMgGZA)

## See also

- `references/codex-lessons.md` - stance/attack-surface/finding-bar adopted from Codex Companion
- `references/output-standards.md` - P0-P3, material bar, header/summary contract
- `PLANS.md` - upgrade plan + future pi-companion plan
- `references/host-detection.md` - the override -> env -> PPID walk priority
- `references/codex-integration.md` - Codex CLI specifics + `forced_login_method` gotcha
- `references/claude-integration.md` - `claude -p --model opus --effort xhigh`
- `references/pi-integration.md` - Pi model chain
- `references/antigravity-integration.md` - Gemini-only ladder through non-interactive Antigravity CLI
- `references/fallback-chain.md` - external chain + Antigravity + degraded path
- `AGENTS.md` - agent-side rules (severity, honesty, anti-recursion contract)

## License

MIT
