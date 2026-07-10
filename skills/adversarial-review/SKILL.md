---
name: adversarial-review
description: "Cross-host adversarial review of any artifact — implementation plans, code/diffs/configs, or prompts/skill definitions. Classifies the input by context, then routes the heavy critique to the agent that is NOT the host (Codex from Claude, Pi chain from Codex, etc.), cross-validates against independent host-side analysis, and returns unified critics with severity ratings and a verdict. Prompts are analyzed host-side across 6 dimensions. Falls back to Gemini via Antigravity, then degraded host-self with explicit warning."
version: 0.7.0
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

## Operating stance (all procedures)

Your job is to **break confidence** in the artifact, not to validate it.

- Default to skepticism. Assume subtle, high-cost, or user-visible failure until
  evidence says otherwise.
- Do **not** give credit for good intent, partial fixes, or “likely follow-up”.
- Happy-path-only behavior is a real weakness.
- Be aggressive, but **grounded**: every finding must be defensible from the
  provided context or tool output. Do not invent files, lines, attack chains,
  or runtime behavior. If you infer, say so and keep confidence honest.
- **Finding bar**: report only material findings. No style, naming, low-value
  cleanup, or speculation without evidence. Prefer **one strong finding** over
  several weak ones. If it looks safe, say so and return no findings.
- Each finding must answer:
  1. What can go wrong?
  2. Why is this path vulnerable?
  3. What is the likely impact?
  4. What concrete change reduces the risk?

See `references/codex-lessons.md` for the Codex Companion sources of this stance.

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

### Focus text (steerable)

If the user supplies a focus area (e.g. “race conditions in checkout”, “auth
boundary”, “rollback”), **weight it heavily** in the partner prompt and in your
own pass. Still report any other **material** issue you can defend — focus is a
priority hint, not a blindfold. Pass focus into the templates as `{FOCUS_TEXT}`
(use `none` when absent).

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

External-reviewer prompt template (replace `{PLAN_TEXT}` and `{FOCUS_TEXT}`):

```
You are an adversarial plan reviewer. Your job is to break confidence in this
plan, not to validate it. Assume it will fail in expensive or subtle ways.
Prove it. Do not credit good intent or likely follow-up work.

FOCUS (weight heavily; still report other material issues): {FOCUS_TEXT}

PLAN:
{PLAN_TEXT}

Attack the plan for:
1. Scope misalignment — does the plan match stated objectives, or smuggle work?
2. Missing steps — testing, migration, rollback, observability, auth?
3. Dependency ordering — can steps run as ordered? Hidden circular deps?
4. Rollback / partial failure — what if step N fails mid-way? Reversible?
5. Blast radius — what existing functionality dies if this ships wrong?
6. Success criteria — verifiable completion conditions, or vibes?
7. Cost / complexity — files touched, migration risk, test impact understated?
8. Assumptions that stop being true under load, empty state, or multi-tenant use.

Finding bar: material only. Each finding answers: what fails, why the plan is
vulnerable, impact, concrete change. Prefer one strong finding over many weak
ones. No style nits. If the plan is sound, say so and return no findings.

Output language: same as the input plan.
Sections: BLOCKERS / SHOULD FIX / NICE TO HAVE / VERDICT
Per finding: P0-P3 severity, evidence (line of plan), problem, impact,
recommendation.
Verdict: PROCEED / REVIEW_NEEDED / RETHINK
Opening line: terse ship/no-ship assessment of the plan (not a neutral recap).
Provide an improved version of the plan incorporating the recommendations.
```

Then: independent host-side pass over the same checklist (without looking at
the partner's output) → cross-validate → unified output with verdict
PROCEED | REVIEW_NEEDED | RETHINK, critics, a complete **Revised Plan** (full
text, not a diff), and **Key Changes from Original**.

## Procedure B — Code review (red team)

External-reviewer prompt template (replace `{CODE_TEXT}`, `{TARGET_LABEL}`,
and `{FOCUS_TEXT}`):

```
You are performing an adversarial software review.
Your job is to break confidence in the change, not to validate it.

Target: {TARGET_LABEL}
User focus: {FOCUS_TEXT}

Default to skepticism. Assume the change can fail in subtle, high-cost, or
user-visible ways until the evidence says otherwise. Do not give credit for
good intent, partial fixes, or likely follow-up work. Happy-path-only = weakness.

CODE / DIFF:
{CODE_TEXT}

Prioritize expensive, dangerous, or hard-to-detect failures:
- auth, permissions, tenant isolation, and trust boundaries
- data loss, corruption, duplication, and irreversible state changes
- rollback safety, retries, partial failure, and idempotency gaps
- race conditions, ordering assumptions, stale state, and re-entrancy
- empty-state, null, timeout, and degraded dependency behavior
- version skew, schema drift, migration hazards, and compatibility regressions
- observability gaps that would hide failure or make recovery harder

Also cover classic failure classes when material:
- SECURITY: injection, auth bypass, data exposure, secrets, crypto misuse, SSRF
- CORRECTNESS: off-by-one, type confusion, null paths, timezone/locale, overflow
- SUPPLY CHAIN: pins, lockfile, typo-squat — only if evidence in the change

Method: actively try to disprove the change. Trace bad inputs, retries,
concurrent actions, and partial completion through the code. Weight the user
focus heavily, but still report any other material issue you can defend.

Finding bar — each finding must answer:
1. What can go wrong?
2. Why is this code path vulnerable?
3. What is the likely impact?
4. What concrete change would reduce the risk?

Report only material findings. No style, naming, low-value cleanup, or
speculation without evidence. Prefer one strong finding over several weak ones.
If the change looks safe, say so directly and return no findings.

Grounding: every finding must be defensible from the provided context. Do not
invent files, lines, incidents, or runtime behavior. Mark inferences and keep
confidence honest.

Output language: same as the input.
Opening line: terse ship/no-ship assessment (not a neutral recap).
Sections: BLOCKERS / SHOULD FIX / NICE TO HAVE / VERDICT
Per finding: P0-P3 severity, evidence (file:line or quote), problem, impact /
exploit scenario, recommendation, confidence (high|medium|low).
Verdict: SHIP / REVIEW_NEEDED / DO_NOT_MERGE
```

Then: independent host-side adversarial pass (same stance and attack surface,
without looking at the partner's output) → cross-validate → unified output
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
- **Target**: <working tree | branch vs base | file | pasted artifact>
- **Focus**: <user focus or none>
- **Verdict**: <see procedure>
- **Findings**: N total - X P0, Y P1, Z P2, W P3
```

Immediately after the header: **≤200 tokens** ship/no-ship summary (top risks
only). Then findings. Drop P3 before P2 if you must cut; never drop P0/P1.

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

Apply the same material-only finding bar: no cosmetic rewrites without a
defensible failure mode.

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

- `references/codex-lessons.md` — what we took from Codex Companion (and what we didn't)
- `references/host-detection.md` — how `lib/detect-host.sh` decides
- `references/codex-integration.md` — Codex CLI invocation, incl. the
  `forced_login_method = "chatgpt"` gotcha
- `references/claude-integration.md` — `claude -p --model opus --effort xhigh`
- `references/grok-integration.md` — `grok -p -m grok-4.5 --reasoning-effort xhigh`
- `references/pi-integration.md` — Pi model chain
- `references/antigravity-integration.md` — Gemini via Antigravity CLI
- `references/fallback-chain.md` — full external chain + degraded path
- `references/output-standards.md` — P0-P3 schema, evidence requirements
