---
name: coding-adversarial-review
description: "Cross-host adversarial red-team review of code, configs, and diffs. Routes the review to the agent that is NOT the host. Codex from Claude, Claude Opus from Codex, Codex/Claude from Grok Build CLI, with Grok and Pi/opencode-go model chain as secondary externals. Cross-validates against your own independent analysis and returns unified security/robustness critics with severity ratings. Falls back to Gemini via Antigravity, then degraded host-self with explicit warning."
version: 0.5.0
model: inherit
allowed-tools: ["Read", "Grep", "Glob", "Bash"]
triggers:
  - "adversarial.?code"
  - "adversarial.?review"
  - "red.?team"
  - "security.?review"
  - "what.?could.?go.?wrong"
  - "find.?vulnerabilit"
  - "threat.?model"
  - "code.?review.?codex"
---

# Adversarial Code Review

Red-team review of code / configs / diffs. The host (you, the agent reading
this) **must not review your own work** - route the heavy critique to the
other agent. This SKILL.md is the same in Claude Code and Codex;
`lib/call-external.sh` detects which host you are and picks the opposite
partner.

## Cross-host principle

- You are running in **Claude Code** -> external reviewer is **Codex**, then
  **Grok Build CLI (Composer 2.5)**, then **Pi/opencode-go model chain** if Codex fails
- You are running in **Codex** -> external reviewer is **Claude (Opus, xhigh)**,
  then **Grok Build CLI (Composer 2.5)**, then **Pi/opencode-go model chain** if Claude fails
- You are running in **Grok Build CLI** -> external reviewer is **Codex**, then
  **Claude (Opus, xhigh)**, then **Pi/opencode-go model chain**. Never Grok itself
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

### 1. Resolve the input

- **Inline code**: use directly.
- **File path**: read the file with the `Read` tool, include the content.
- **"review uncommitted"**: gather the diff via `git diff` (or `git diff --staged`).
- **"review --base main"**: use `git diff main...HEAD`.
- **Plan or design doc** -> suggest `/adversarial-review:adversarial-plan-review`
  instead and stop here.
- **Prompt or skill spec** -> suggest `/adversarial-review:prompt-optimize`
  instead and stop here.
- No input -> ask: "What code should I review? Paste it, point to a file, or
  say 'review uncommitted'."

### 2. Build the external-reviewer prompt

Use this template, replacing `{CODE_TEXT}` with the actual code/diff:

```
You are a red-team security and reliability analyst. Assume everything will
fail. Prove it with concrete exploit scenarios.

CODE:
{CODE_TEXT}

Review for:
1. SECURITY: injection, auth bypass, data exposure, OWASP top 10, secrets,
   crypto misuse, deserialization, SSRF.
2. ROBUSTNESS: race conditions, failure cascades, resource exhaustion,
   timeouts, error handling gaps, retry storms.
3. CORRECTNESS: off-by-one, type confusion, null/undef paths, locale/timezone,
   floating-point, integer overflow.
4. CONCURRENCY: data races, deadlocks, ordering, cache coherence.
5. OBSERVABILITY: missing logs at failure points, secrets in logs, metric gaps.
6. SUPPLY CHAIN: pinned versions? lockfile? typo-squat risk?
7. BLAST RADIUS: who else does this break if deployed?

Output language: same as the input.
Sections: BLOCKERS / SHOULD FIX / NICE TO HAVE / VERDICT
Per finding: P0-P3 severity, evidence (file:line or quote), problem,
exploit/scenario, recommendation.
Verdict: SHIP / REVIEW_NEEDED / DO_NOT_MERGE
```

If the code is over ~6 kB, focus the diff on changed regions and provide
necessary context - long prompts can stall the external backend.

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
- Do **not** call `codex exec`, `claude -p`, `grok -p`, or `pi -p` directly - always go
  through `lib/call-external.sh`. The script enforces anti-recursion via the
  `ADVERSARIAL_REVIEW_DEPTH` env counter.
- Grok external calls default to `grok-composer-2.5-fast`. Override with
  `ADVERSARIAL_REVIEW_GROK_MODEL` if needed.
- Pi external calls default to this opencode-go model chain:
  `opencode-go/glm-5.2:high`, `opencode-go/deepseek-v4-pro:xhigh`,
  `opencode-go/deepseek-v4-flash:xhigh`. For DeepSeek models, `xhigh` maps to
  provider max thinking. Override with `ADVERSARIAL_REVIEW_PI_MODELS` if needed.
  Do not move the call to `/tmp`, because Doppler-scoped opencode-go credentials
  resolve from the current directory on this machine.
- Gemini fallback must run through non-interactive Antigravity CLI:
  `agy --print --print-timeout "${ADVERSARIAL_REVIEW_TIMEOUT:-300}s" --sandbox`.
  Do not call the standalone `gemini` CLI for this fallback.
- If exit is `1` (recursion), you are inside a partner-launched call; emit a
  short note ("recursion guard tripped - parent already running review") and
  stop. Do not produce a self-review.

### 4. Run your own independent red-team analysis (host-side)

Without looking at the partner's output, walk the same checklist (security,
robustness, correctness, concurrency, observability, supply chain, blast
radius). This is your host-side draft.

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
## Adversarial Code Review

- **Mode**: <external=codex | external=claude-opus | external=grok-composer-2.5-fast | external=pi-glm-5.2 | external=pi-deepseek-v4-pro | external=pi-deepseek-v4-flash | external=antigravity-gemini | DEGRADED>
- **Verdict**: SHIP | REVIEW_NEEDED | DO_NOT_MERGE
- **Findings**: N total - X P0, Y P1, Z P2, W P3

### Critics

#### [P0]: <title>  [cross-validated | external-only | host-only]
- **Problem**: <what's wrong, why it matters>
- **Evidence**: <file:line, quote, or scenario>
- **Exploit / scenario**: <concrete failure mode>
- **Recommendation**: <specific fix>

[…repeat, highest severity first…]

### Recommended Patch

<minimal patch addressing P0/P1, in unified-diff form when practical;
prose otherwise>

### Key Risks if Merged As-Is

1. <risk> - <impact>
2. <risk> - <impact>
```

**If `lib/call-external.sh` exited `2` (degraded mode)**, prepend this banner
verbatim to the top of the output, before the `## Adversarial Code Review`
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
- `references/grok-integration.md` - `grok -p -m grok-composer-2.5-fast` headless path
- `references/pi-integration.md` - Pi/opencode-go model chain
- `references/antigravity-integration.md` - Gemini through non-interactive Antigravity CLI
- `references/fallback-chain.md` - full external chain + Antigravity + degraded path
- `references/output-standards.md` - P0-P3 schema, evidence requirements
