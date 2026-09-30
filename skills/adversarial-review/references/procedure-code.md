Read [the common skill](../SKILL.md) first: its shared verification preamble, routing, wrapper, cross-validation and output obligations apply to this procedure.

## Procedure B — Code review (red team)

External-reviewer prompt template (replace `{CODE_TEXT}`, `{TARGET_LABEL}`,
and `{FOCUS_TEXT}`; prepend the shared verification preamble):

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
with verdict SHIP | REVIEW_NEEDED | DO_NOT_MERGE and findings. Include a
**Recommended Patch** (unified diff when practical) only for actionable accepted
findings or an explicit request, and **Key Risks if Merged As-Is** when present.
With no accepted findings, return concise no-findings, evidence, and verdict.
