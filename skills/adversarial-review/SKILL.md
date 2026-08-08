---
name: adversarial-review
description: "Cross-host adversarial review of implementation plans, code/diffs/configs, or prompts/skill definitions. Classifies the artifact, routes the heavy critique to the agent that is NOT the host, cross-validates against independent host-side analysis, and returns material findings with severity and a verdict. Plan/code reviews include a mandatory over-engineering, YAGNI, and in-repo reuse counterfactual. Prompts are analyzed host-side across 6 dimensions. Provider routing includes OpenCode Go DeepSeek V4 Flash xhigh, Moonshot Kimi K3, direct-xAI Grok 4.5 high, and Gemini 3.6 Flash High first in the Antigravity ladder before explicit degraded mode."
version: 0.9.3
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
- **Unnecessary complexity can be part of the material risk surface**: for every
  plan/code review, hold required behavior and safety fixed, then challenge
  speculative layers, false seams, duplicated ownership, and unused
  flexibility. Treat line count and framework choice as clues, never verdicts.
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

### Simplicity evidence preflight (plan and code)

When the artifact targets a repository, use targeted `Grep` / `Glob` before
dispatch: search exact changed symbols, capability/domain terms, and the names
of new modules, hooks, flags, adapters, or seams. Treat the repository as an
Effect codebase only when its manifests or imports establish that. Then search
for existing Effect functions, Services, and Layers that own the same concern.
Include only relevant path/line evidence and short excerpts in the partner
prompt. Absence of a match is not proof; never claim duplicate ownership without
a concrete existing owner. Without repository access, review only the artifact
and do not claim missed in-repo reuse.

## Cross-host principle (plan and code reviews)

- Host **Claude Code** → order depends on the artifact (user decision
  2026-07-11, wired via `ADVERSARIAL_REVIEW_ARTIFACT`):
  - **Code/diff/config review** (`ADVERSARIAL_REVIEW_ARTIFACT=code`, the
    script's default): **direct xAI via Grok CLI** first, using `grok-4.5`
    at high, then **Codex (GPT-5.6 Luna, max)**, then **Pi model chain**.
    The diff under review is normally
    Codex-authored, so Codex reviewing it would be same-family; Grok keeps
    the cross-family property.
  - **Plan review** (`ADVERSARIAL_REVIEW_ARTIFACT=plan`): **Codex (GPT-5.6
    Luna, max)** first,
    then **direct xAI via Grok CLI**, then **Pi model chain**. Plans are
    architect(Claude)-authored, so Codex is the cross-family reviewer there.
- Host **Codex** → external is **Pi model chain** starting with Pi xAI OAuth
  Grok 4.5 (`xai-oauth/grok-4.5` with `--thinking xhigh`), then OpenCode Go DeepSeek V4 Flash xhigh, then
  direct Moonshot Kimi K3 xhigh, then **Claude (Opus, xhigh)**, then direct xAI
  via Grok CLI
- Host **Grok Build CLI** → **Codex (GPT-5.6 Luna, max)**, then **Claude (Opus, xhigh)**, then
  **non-xAI Pi chain** (DeepSeek, then direct Moonshot Kimi K3 xhigh). Never Grok itself
- Host **Pi** → **Codex (GPT-5.6 Luna, max)**, then **Claude (Opus, xhigh)**,
  then **direct xAI via Grok CLI**. Never Pi itself
- All externals unavailable → **DEGRADED MODE**: host self-review with explicit
  banner. Never silently auto-review.

### Local Claude CLI authorization

On this machine/user setup, programmatic non-interactive Claude CLI use is
standing-approved for this skill. Do not re-ask solely to call `claude -p` as
the external reviewer from Codex/Grok hosts. The invocation uses `--bare` and
`--tools ""`, so the reviewer receives only the supplied prompt and has no tool
access. Scope: review-only critique. It
does not authorize code edits, git writes, issue/PR mutations, deployments,
credential changes, or broader machine control. Still honor any per-turn user
constraints such as requested model, effort, timeout, or read-only limits.

## Calling the external partner

Pipe the prompt into `lib/call-external.sh` (handles host detection, routing,
anti-recursion, the Antigravity model ladder, and degraded mode):

```bash
# ARTIFACT comes from Step 0: "plan" for plan reviews, "code" for
# code/diff/config reviews (also the safe default when mixed/ambiguous).
echo "$PROMPT" | ADVERSARIAL_REVIEW_ARTIFACT="$ARTIFACT" bash "$PLUGIN_DIR/lib/call-external.sh"
echo "exit=$?"
```

- **stdout** = partner's analysis; **stderr** = operational logs;
  **exit** = `0` external success, `2` degraded, `1` error/recursion.
- Do **not** call `codex exec`, `claude -p`, `grok -p`, or `pi -p` directly —
  always go through `lib/call-external.sh` (anti-recursion via
  `ADVERSARIAL_REVIEW_DEPTH`).
- Direct xAI via Grok CLI defaults to the model `grok-4.5`, authenticated by
  inherited `XAI_API_KEY`. The script checks `grok models`, skips unavailable
  entries, and uses high, the highest effort accepted by the current Grok CLI.
  Grok 4.5 is xAI's frontier model. Override the chain via
  `ADVERSARIAL_REVIEW_GROK_MODELS`; the singular
  `ADVERSARIAL_REVIEW_GROK_MODEL` remains a back-compat override.
- Codex external is pinned to `gpt-5.6-luna` with
  `-c model_reasoning_effort=max`, independently of the interactive Codex
  default. Model and effort are intentionally not overridable: this route is
  review-only and always uses `--sandbox read-only`.
- Pi model chain default: `xai-oauth/grok-4.5` with `--thinking xhigh`,
  `opencode-go/deepseek-v4-flash:xhigh`, `moonshotai/kimi-k3:xhigh` (Moonshot direct via
  `MOONSHOT_API_KEY`). Override via `ADVERSARIAL_REVIEW_PI_MODELS`.
  Override the Pi thinking flag via `ADVERSARIAL_REVIEW_PI_THINKING`; default
  is `xhigh` for the first explicit model token without a `:level` suffix.
  Do not move the call to `/tmp` — Doppler-scoped opencode-go credentials
  resolve from the current directory.
- Antigravity fallback discovers models with `agy models`, then tries a
  quality-first cross-provider ladder. The default starts with Gemini 3.6
  Flash High, then Claude Opus 4.6 Thinking, Gemini 3.1 Pro High, Claude Sonnet
  4.6, GPT OSS 120B Medium, and Gemini 3.6 Flash Medium. A failed quota or call advances
  to the next listed model. Override via
  `ADVERSARIAL_REVIEW_ANTIGRAVITY_MODELS`. Never use the standalone `gemini`
  CLI.
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
7. Delivery-cost underestimation: migration, rollout, test, and operational
   impact understated?
8. Assumptions that stop being true under load, empty state, or multi-tenant use.
9. Over-engineering / YAGNI: holding required behavior and safety fixed, could
   the plan use fewer concepts, layers, files, or configuration surfaces? Is
   each new seam justified by a current caller/adapter? Does an existing
   in-repo module, including a canonical Effect implementation, already own the
   concern? Treat fewer lines as a clue, never a target; do not introduce Effect
   unless repo standards or existing ownership already call for it.

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

Also run a simplicity counterfactual (material only; hold required behavior and
safety fixed):
- Could the same change use fewer concepts, layers, entry points, or
  configuration surfaces?
- Is every new abstraction, type, hook, flag, adapter, and seam required by the
  current spec or a verified caller?
- If a new layer were deleted, would complexity reappear across callers, or
  simply vanish as pass-through / middle-man code? Is a second adapter real or
  hypothetical?
- Does an existing in-repo module already own this concern or logic shape? If a
  canonical Effect implementation exists, call or extend it instead of creating
  parallel ownership.
- Could materially fewer lines expose duplication or unnecessary machinery?
  LOC is only a clue. Never trade away tests, error handling, observability, or
  required behavior, and do not introduce Effect solely to satisfy this check.

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

For over-engineering findings, name the unrequired concept/layer or duplicate
owner, cite a path/line or plan section plus current-spec/caller/reuse evidence,
state the material failure, maintenance cost, or risk, and give a concrete
simpler alternative that preserves required behavior and safety. "Could use
fewer lines" or "Effect would be cleaner" alone is not a finding.

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

- **Mode**: <external=codex-luna-max | external=claude-opus | external=direct-xai-* | external=pi-grok-4.5-xhigh | external=pi-* | external=antigravity-* | DEGRADED>
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

Run the analogous simplicity counterfactual for prompts: can the same behavior
be preserved with fewer duplicated rules, layers of indirection, or special
cases? Shorter is a clue, not the goal.

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
- `references/grok-integration.md`: direct-xAI model discovery and fallback
- `references/pi-integration.md`: Pi model chain, including Moonshot Kimi K3
- `references/antigravity-integration.md`: multi-provider model ladder
- `references/fallback-chain.md`: full external chain and degraded path
- `references/output-standards.md`: P0-P3 schema and evidence requirements
