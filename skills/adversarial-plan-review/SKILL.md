---
name: adversarial-plan-review
description: "Cross-host adversarial review of an implementation plan. Routes the review to the agent that is NOT the host. Codex from Claude, Claude Opus from Codex, Codex/Claude from Grok Build CLI, with Grok and Pi model chain as secondary externals. Cross-validates against your own independent analysis, returns a revised plan with critics and a verdict. Falls back to Gemini via Antigravity, then degraded host-self with an explicit warning."
version: 0.5.0
model: inherit
allowed-tools: ["Read", "Grep", "Glob", "Bash"]
triggers:
  - "adversarial.?plan"
  - "review.?plan"
  - "validate.?plan"
  - "check.?plan"
  - "plan.?review"
  - "before.?implement"
---

# Adversarial Plan Review

Pre-implementation review of a plan. The host (you, the agent reading this)
**must not review your own work** - route the heavy critique to the other
agent. This SKILL.md is the same in Claude Code and Codex; `lib/call-external.sh`
detects which host you are and picks the opposite partner.

## Cross-host principle

- You are running in **Claude Code** -> external reviewer is **Codex**, then
  **Grok Build CLI (Composer 2.5)**, then **Pi model chain** if Codex fails
- You are running in **Codex** -> external reviewer is **Claude (Opus, xhigh)**,
  then **Grok Build CLI (Composer 2.5)**, then **Pi model chain** if Claude fails
- You are running in **Grok Build CLI** -> external reviewer is **Codex**, then
  **Claude (Opus, xhigh)**, then **Pi model chain**. Never Grok itself
- You are running in **Pi** -> external reviewer is **Codex**, then
  **Claude (Opus, xhigh)**, then **Grok Build CLI**. Never Pi itself
- All externals unavailable -> **DEGRADED MODE**: host self-review with explicit
  banner. Never silently auto-review.

### Local Claude CLI authorization

On this machine/user setup, programmatic non-interactive Claude CLI use is
standing-approved for this adversarial-review skill family. Do not re-ask solely
to call `claude -p` as the external reviewer from Codex/Grok hosts. Scope this
authorization to review-only critique: it does not authorize code edits, git
writes, issue/PR mutations, deployments, credential changes, or broader machine
control. Still honor any per-turn user constraints such as requested model,
effort, timeout, or read-only/tooling limits.

## How to execute

### 1. Resolve the plan

If user gave plan text inline -> use it.
If user pointed to a file -> use the `Read` tool on the file.
If input is **code or a diff** -> suggest `/adversarial-review:coding-adversarial-review`
instead and stop here.
If no input -> ask: "What plan should I review? Paste it or point to a file."

### 2. Build the external-reviewer prompt

Use this template, replacing `{PLAN_TEXT}` with the actual plan:

```
You are an adversarial plan reviewer. Assume this plan will fail. Prove it.

PLAN:
{PLAN_TEXT}

Validate for:
1. Scope alignment - does the plan match stated objectives?
2. Missing steps - gaps in sequence (testing, migration, rollback)?
3. Dependency ordering - can steps execute as ordered? Circular deps?
4. Rollback strategy - what if step N fails? Reversible?
5. Blast radius - what existing functionality is at risk?
6. Success criteria - verifiable completion conditions?
7. Cost estimate - complexity, files changed, test impact

Output language: same as the input plan.
Sections: BLOCKERS / SHOULD FIX / NICE TO HAVE / VERDICT
Per finding: P0-P3 severity, evidence (line of plan), problem, recommendation.
Verdict: PROCEED / REVIEW_NEEDED / RETHINK
Provide an improved version of the plan incorporating the recommendations.
```

Keep the prompt focused. If the plan is over ~6 kB, summarize sections instead
of pasting raw - long prompts can stall the external backend.

### 3. Call the external partner

Pipe the prompt into `lib/call-external.sh` (this script handles host detection,
routing, anti-recursion, Gemini via Antigravity fallback, and degraded mode):

```bash
PLUGIN_DIR="$HOME/repos/coding-plugins/adversarial-review"  # or wherever installed
echo "$PROMPT" | bash "$PLUGIN_DIR/lib/call-external.sh"
echo "exit=$?"
```

Capture:
- **stdout** = the partner's analysis (or degraded host-self if all failed)
- **stderr** = operational logs (which partner was used, latency, fallback chain)
- **exit code** = `0` external success, `2` degraded, `1` error/recursion

Notes:
- Do **not** call `codex exec`, `claude -p`, `grok -p`, or `pi -p` directly - always go through
  `lib/call-external.sh`. The script enforces anti-recursion via the
  `ADVERSARIAL_REVIEW_DEPTH` env counter.
- Grok external calls default to `grok-composer-2.5-fast` through Grok CLI.
  Preferred auth is inherited `XAI_API_KEY`, not OpenRouter. Override with
  `ADVERSARIAL_REVIEW_GROK_MODEL` only if explicitly requested.
- Pi external calls default to this Pi model chain:
  Pi default config, `opencode-go/glm-5.2:high`, `moonshotai/kimi-k2.7-code-highspeed`.
  The Moonshot leg is direct API via `MOONSHOT_API_KEY`, not OpenRouter.
  `default` means Pi's configured provider, model, and thinking level. Override
  with `ADVERSARIAL_REVIEW_PI_MODELS` if needed.
  Do not move the call to `/tmp`, because Doppler-scoped opencode-go credentials
  resolve from the current directory on this machine.
- Gemini fallback must run through non-interactive Antigravity CLI:
  `agy --print --print-timeout "${ADVERSARIAL_REVIEW_TIMEOUT:-300}s" --sandbox`.
  Do not call the standalone `gemini` CLI for this fallback.
- If exit is `1` (recursion), you are inside a partner-launched call; emit a
  short note ("recursion guard tripped - parent already running review") and
  stop. Do not produce a self-review.

### 4. Run your own independent analysis (host-side)

Without looking at the partner's output, walk the same checklist (scope, missing
steps, ordering, rollback, blast radius, success criteria). This is your
host-side draft.

### 5. Cross-validate

Compare host-side findings with the partner's:

| Tag                 | Meaning                                          |
|---------------------|--------------------------------------------------|
| `[cross-validated]` | both you and partner caught it (high confidence) |
| `[external-only]`   | only the partner caught it                       |
| `[host-only]`       | only you caught it                               |

On severity disagreements, take the higher of the two.

### 6. Return unified output

Format:

```markdown
## Adversarial Plan Review

- **Mode**: <external=codex | external=claude-opus | external=grok-composer-2.5-fast | external=pi-default | external=pi-glm-5.2 | external=pi-moonshotai-kimi-k2.7-code-highspeed | external=antigravity-gemini | DEGRADED>
- **Verdict**: PROCEED | REVIEW_NEEDED | RETHINK
- **Findings**: N total - X P0, Y P1, Z P2, W P3

### Critics

#### [P0]: <title>  [cross-validated | external-only | host-only]
- **Problem**: <what's wrong, why it matters>
- **Evidence**: <line of plan, quote>
- **Recommendation**: <specific fix>

[…repeat, highest severity first…]

### Revised Plan

<the complete improved plan, ready to execute - full text, not a diff>

### Key Changes from Original

1. <change> - <why>
2. <change> - <why>
```

**If `lib/call-external.sh` exited `2` (degraded mode)**, prepend this banner
verbatim to the top of the output, before the `## Adversarial Plan Review`
heading:

```
> ⚠️ **DEGRADED MODE** - no external partner reachable. Output below is
> single-perspective host self-review and violates the cross-host principle.
> Re-run after restoring access to Codex / Claude / Grok / Pi / Antigravity for higher confidence.
```

## References

- `references/host-detection.md` - how `lib/detect-host.sh` decides
- `references/codex-integration.md` - Codex CLI invocation, including the
  `forced_login_method = "chatgpt"` gotcha for ChatGPT-account auth
- `references/claude-integration.md` - `claude -p --model opus --effort xhigh`
- `references/pi-integration.md` - Pi model chain
- `references/antigravity-integration.md` - Gemini through non-interactive Antigravity CLI
- `references/fallback-chain.md` - full external chain + Antigravity + degraded path
- `references/output-standards.md` - P0-P3 schema, evidence requirements
