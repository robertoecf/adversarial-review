---
name: adversarial-review
description: "Cross-host adversarial review of any artifact — implementation plans, code/diffs/configs, or prompts/skill definitions. Classifies the input by context, then routes the heavy critique to the agent that is NOT the host (Codex from Claude, Pi chain from Codex, etc.), cross-validates against independent host-side analysis, and returns unified critics with severity ratings and a verdict. Prompts are analyzed host-side across 6 dimensions. Falls back to Gemini via Antigravity, then degraded host-self with explicit warning."
version: 0.6.1
model: inherit
allowed-tools: ["Read", "Grep", "Glob", "Bash"]
triggers:
  - "adversarial.?review"
  - "adversarial.?plan"
  - "adversarial.?code"
  - "review.?plan"
  - "plan.?review"
  - "red.?team"
  - "security.?review"
  - "what.?could.?go.?wrong"
  - "prompt.?optimi"
  - "review.?prompt"
  - "review.?all"
  - "full.?review"
---

# Adversarial Review

One skill for all adversarial review. Classify the input, then run the matching
procedure. The host (you, the agent reading this) **must not review your own
work** — for plans and code, route the heavy critique to the other agent via
`lib/call-external.sh`. Prompt analysis is host-side.

```bash
PLUGIN_DIR="$HOME/repos/skills/plugins/adversarial-review"
```

## Step 0 — Classify the input

| Input type          | Detection heuristic                                                                | Procedure        |
|---------------------|------------------------------------------------------------------------------------|------------------|
| Implementation plan | Numbered steps, "plan:", phase/step structure, files/modules to change             | **Plan review**  |
| Code / diff / config| Code syntax, function definitions, diff markers (`+++`, `---`, `@@`), config files | **Code review**  |
| Prompt / instruction| "you are…", system-prompt language, SKILL.md, YAML frontmatter with `triggers:`    | **Prompt review**|
| Mixed               | Multiple signals — pick the dominant one, note the rest                            | dominant type    |
| Ambiguous           | Can't classify confidently — say what you see and ask                              | —                |

Resolve the input first: inline text → use it; file path → `Read` it;
"review uncommitted" → `git diff` (or `--staged`); "review --base main" →
`git diff main...HEAD`. No input → ask for it.

## Cross-host principle (plan and code reviews)

- Host **Claude Code** → external is **Codex**, then **Grok Build CLI
  (Grok 4.5 xhigh)**, then **Pi model chain**
- Host **Codex** → external is **Pi model chain** starting with Pi xAI OAuth
  Grok 4.5 (`xai-oauth/grok-4.5` with `--thinking xhigh`), then Pi fallbacks, then
  **Claude (Opus, xhigh)**, then **Grok Build CLI**
- Host **Grok Build CLI** → **Codex**, then **Claude (Opus, xhigh)**, then
  **Pi model chain**. Never Grok itself
- Host **Pi** → **Codex**, then **Claude (Opus, xhigh)**, then **Grok Build
  CLI**. Never Pi itself
- All externals unavailable → **DEGRADED MODE**: host self-review with explicit
  banner. Never silently auto-review.

### Local Claude CLI authorization

On this machine/user setup, programmatic non-interactive Claude CLI use is
standing-approved for this skill. Do not re-ask solely to call `claude -p` as
the external reviewer from Codex/Grok hosts. Scope: review-only critique — it
does not authorize code edits, git writes, issue/PR mutations, deployments,
credential changes, or broader machine control. Still honor any per-turn user
constraints such as requested model, effort, timeout, or read-only limits.

## Calling the external partner

Pipe the prompt into `lib/call-external.sh` (handles host detection, routing,
anti-recursion, Gemini-via-Antigravity fallback, degraded mode):

```bash
echo "$PROMPT" | bash "$PLUGIN_DIR/lib/call-external.sh"
echo "exit=$?"
```

- **stdout** = partner's analysis; **stderr** = operational logs;
  **exit** = `0` external success, `2` degraded, `1` error/recursion.
- Do **not** call `codex exec`, `claude -p`, `grok -p`, or `pi -p` directly —
  always go through `lib/call-external.sh` (anti-recursion via
  `ADVERSARIAL_REVIEW_DEPTH`).
- Grok external defaults to `grok-4.5` with `--reasoning-effort xhigh` via Grok CLI, auth by
  inherited `XAI_API_KEY`. Override model via `ADVERSARIAL_REVIEW_GROK_MODEL`
  and effort via `ADVERSARIAL_REVIEW_GROK_EFFORT`.
- Pi model chain default: `xai-oauth/grok-4.5` with `--thinking xhigh`,
  `opencode-go/glm-5.2:high`, `moonshotai/kimi-k2.7-code-highspeed` (Moonshot
  direct via `MOONSHOT_API_KEY`). Override via `ADVERSARIAL_REVIEW_PI_MODELS`.
  Override the Pi thinking flag via `ADVERSARIAL_REVIEW_PI_THINKING`; default
  is `xhigh` for the first explicit model token without a `:level` suffix.
  Do not move the call to `/tmp` — Doppler-scoped opencode-go credentials
  resolve from the current directory.
- Gemini fallback runs only through non-interactive Antigravity CLI:
  `agy --print --print-timeout "${ADVERSARIAL_REVIEW_TIMEOUT:-300}s" --sandbox`.
  Never the standalone `gemini` CLI.
- Exit `1` (recursion): you are inside a partner-launched call — emit a short
  note ("recursion guard tripped - parent already running review") and stop.
- Input over ~6 kB: summarize sections / focus the diff on changed regions —
  long prompts can stall the external backend.

## Procedure A — Plan review

External-reviewer prompt template (replace `{PLAN_TEXT}`):

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

Then: independent host-side pass over the same checklist (without looking at
the partner's output) → cross-validate → unified output with verdict
PROCEED | REVIEW_NEEDED | RETHINK, critics, a complete **Revised Plan** (full
text, not a diff), and **Key Changes from Original**.

## Procedure B — Code review (red team)

External-reviewer prompt template (replace `{CODE_TEXT}`):

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

Then: independent host-side red-team pass → cross-validate → unified output
with verdict SHIP | REVIEW_NEEDED | DO_NOT_MERGE, critics, a **Recommended
Patch** (unified diff when practical), and **Key Risks if Merged As-Is**.

## Cross-validation (procedures A and B)

| Tag                 | Meaning                                          |
|---------------------|--------------------------------------------------|
| `[cross-validated]` | both you and partner caught it (high confidence) |
| `[external-only]`   | only the partner caught it                       |
| `[host-only]`       | only you caught it                               |

On severity disagreements, take the higher of the two.

Unified output header (both procedures):

```markdown
## Adversarial Review — <Plan | Code>

- **Mode**: <external=codex | external=claude-opus | external=grok-4.5-xhigh | external=pi-grok-4.5-xhigh | external=pi-* | external=antigravity-gemini | DEGRADED>
- **Verdict**: <see procedure>
- **Findings**: N total - X P0, Y P1, Z P2, W P3
```

**If `lib/call-external.sh` exited `2`**, prepend this banner verbatim before
the heading:

```
> ⚠️ **DEGRADED MODE** - no external partner reachable. Output below is
> single-perspective host self-review and violates the cross-host principle.
> Re-run after restoring access to Codex / Claude / Grok / Pi / Antigravity for higher confidence.
```

## Procedure C — Prompt review (host-side, no external call)

Analyze across 6 dimensions: **clarity** (ambiguity, undefined terms, vague
referents), **specificity** (missing constraints, handwave phrases, missing
examples), **edge cases** (unhandled inputs, boundary conditions, conflicting
scenarios without precedence), **token efficiency** (redundancy, filler,
hedging), **instruction conflicts** (contradictions, precedence ambiguity,
buried overrides), **structural integrity** (buried critical instructions,
poor hierarchy, front/back-loading).

Modes: **A Critique** ("critique this prompt") → issue list only, ≤800 tokens.
**B Optimize** (default) → issues + optimized version + diff + change log,
≤1500 tokens. **C Compare** (two inputs) → side-by-side scoring table +
verdict + hybrid recommendation, ≤1000 tokens.

Rules: preserve intent and voice; every change traces to a finding; if the
prompt is already good, say so — don't manufacture findings. If input has YAML
frontmatter (SKILL.md), analyze frontmatter and body. Input under ~20 tokens →
quick inline feedback, skip the full analysis.

Output per finding: `[P0-P3] [dimension]: title` + evidence (quote) + problem
+ fix.

## References

- `references/host-detection.md` — how `lib/detect-host.sh` decides
- `references/codex-integration.md` — Codex CLI invocation, incl. the
  `forced_login_method = "chatgpt"` gotcha
- `references/claude-integration.md` — `claude -p --model opus --effort xhigh`
- `references/grok-integration.md` — `grok -p -m grok-4.5 --reasoning-effort xhigh`
- `references/pi-integration.md` — Pi model chain
- `references/antigravity-integration.md` — Gemini via Antigravity CLI
- `references/fallback-chain.md` — full external chain + degraded path
- `references/output-standards.md` — P0-P3 schema, evidence requirements
