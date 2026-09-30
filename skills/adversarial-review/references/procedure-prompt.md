Read [the common skill](../SKILL.md) first: its shared verification preamble, routing, wrapper, cross-validation and output obligations apply to this procedure.

## Procedure C: Prompt review (external critique, host adjudication)

Set `ARTIFACT=prompt` and `AUTHOR` when known, using the existing author-aware
routing for unknown authors. Send this template through `lib/call-external.sh`
as above; the same fallback, degraded-mode, and recursion rules apply.

External-reviewer prompt template (replace placeholders; prepend the shared
verification preamble):

```
You are an adversarial prompt reviewer. Review the supplied prompt across
6 dimensions: clarity (ambiguity, undefined terms, vague referents),
specificity (missing constraints, handwave phrases, missing examples),
edge cases (unhandled inputs, boundary conditions, conflicting scenarios
without precedence), token efficiency (redundancy, filler, hedging),
instruction conflicts (contradictions, precedence ambiguity, buried overrides),
and structural integrity (buried critical instructions, poor hierarchy,
front/back-loading).

Focus: {FOCUS_TEXT}
Mode: {PROMPT_MODE}
PROMPT(S):
{PROMPT_TEXT}

Apply the material-only finding bar: no cosmetic rewrites without a defensible
failure mode. Run the simplicity counterfactual: can the same behavior survive
with fewer duplicated rules, indirection layers, or special cases? Shorter is
a clue, not the goal. Preserve intent and voice; every change traces to a
finding. Analyze YAML frontmatter and body when present. If already good,
return no findings rather than manufacture them.

Modes: A Critique: issue list only, <=800 tokens. B Optimize (default): issues
plus optimized version, diff, and change log only when material findings require
changes or explicitly requested, <=1500 tokens. C Compare: side-by-side scoring
table, verdict, and hybrid recommendation when warranted, <=1000 tokens.
For input under ~20 tokens, keep critique brief, still using all six dimensions.

Output language: same as input. Per finding: [P0-P3] [dimension]: title, evidence
(quote), problem, impact, fix, confidence. Conclude with a verdict.
```

Then independently inspect the same six dimensions before reading the partner's
output, adjudicate findings, and apply **Cross-validation** above, including
origin tags and the degraded banner when applicable. Follow the requested mode;
when no changes are warranted, return concise no-findings, evidence, and verdict.
