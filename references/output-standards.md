# Output Standards Reference

## Severity Scale

| Level | Label | Meaning | Action |
|-------|-------|---------|--------|
| P0 | Critical | Exploitable vulnerability, data loss, security breach, irreversible bad state | Must fix before merge/deploy |
| P1 | High | Significant risk, likely failure mode under real use | Should fix in this iteration |
| P2 | Medium | Material quality/reliability issue, limited blast radius | Fix when convenient this cycle |
| P3 | Low | Minor; only if it still fails the material-finding bar | Optional |

P3 is **not** a dump bucket for style nits. If it is only naming/style/cleanup
with no failure scenario, **omit it**.

## Material-finding bar

Include a finding only if it answers all four:

1. What can go wrong?
2. Why is this path / plan step vulnerable?
3. What is the likely impact?
4. What concrete change reduces the risk?

Exclude: style, naming, low-value cleanup, speculative concerns without evidence.

Calibration: prefer one strong finding over several weak ones. Clean review →
empty blockers and an honest SHIP/PROCEED is success, not failure.

For an over-engineering finding, also require:

- a path/line or plan-section anchor for the concrete unrequired concept, layer,
  seam, configuration surface, or duplicate owner;
- evidence from the current spec, verified callers/adapters, or a cited
  existing in-repo implementation, plus the material failure, maintenance cost,
  or risk;
- a concrete simpler alternative that preserves required behavior and safety.

"Could use fewer lines" and "Effect would be cleaner" are clues, not findings.
If the repository already has a canonical Effect implementation for the
concern, duplicating that ownership is evidence; introducing Effect only for
framework consistency is not.

## Per-Finding Template

```markdown
### [P0|P1|P2|P3] [category]: Title
- **Evidence**: [file:line, plan step, or direct quote]
- **Problem**: [what fails and why the path is vulnerable]
- **Impact**: [user/data/security/ops consequence]
- **Options** (optional when tradeoffs matter):
  - A) [option] — effort: [low/med/high], effectiveness: [partial/full]
  - B) [option] — effort: [low/med/high], effectiveness: [partial/full]
  - C) Accept risk — [consequences]
- **Recommendation**: [specific fix]
- **Confidence**: high | medium | low
- **Origin**: [cross-validated] | [external-only] | [host-only]
```

## Unified header

```markdown
## Adversarial Review — <Plan | Code | Prompt>

- **Mode**: <external=... | DEGRADED>
- **Target**: <...>
- **Focus**: <... | none>
- **Verdict**: <SHIP|REVIEW_NEEDED|DO_NOT_MERGE or PROCEED|REVIEW_NEEDED|RETHINK>
- **Findings**: N total - X P0, Y P1, Z P2, W P3
```

## Executive Summary

Immediately after the header:

- Max **200 tokens**
- **Ship/no-ship assessment first** (not a neutral recap)
- Count of findings by severity (or “no material findings”)
- Top 1–2 actionable takeaways only

## Verdict mapping

| Procedure | Verdicts |
|-----------|----------|
| Code | `SHIP` / `REVIEW_NEEDED` / `DO_NOT_MERGE` |
| Plan | `PROCEED` / `REVIEW_NEEDED` / `RETHINK` |
| Prompt | critique list, or optimize/compare modes (no ship verdict required) |

Guidance:

- Any defended **P0** → `DO_NOT_MERGE` / `RETHINK` unless explicitly accepted by user.
- **P1** without P0 → usually `REVIEW_NEEDED`.
- No material findings → `SHIP` / `PROCEED`.

## Confidence Tags

- `high` — clear evidence, well-understood pattern
- `medium` — reasonable inference, some ambiguity
- `low` — speculative; only keep if impact would be severe and path is real

## Token Budget Enforcement

1. Write output naturally
2. If exceeding budget, cut from the bottom (lowest severity first)
3. Never cut P0 or P1 findings
4. If still over budget after dropping P3/P2, note truncation

## Optional JSON shape (non-default)

Markdown remains the default for multi-host synthesis. When a caller asks for
`--json` (future companion / automation), map as:

```json
{
  "verdict": "SHIP|REVIEW_NEEDED|DO_NOT_MERGE",
  "summary": "terse ship assessment",
  "mode": "external=...|DEGRADED",
  "target": "...",
  "focus": "...|none",
  "findings": [
    {
      "severity": "P0|P1|P2|P3",
      "title": "...",
      "body": "problem + impact",
      "evidence": "file:line or quote",
      "recommendation": "...",
      "confidence": 0.0,
      "origin": "cross-validated|external-only|host-only"
    }
  ],
  "next_steps": ["..."]
}
```

Severity string mapping from Codex-style enums: critical→P0, high→P1,
medium→P2, low→P3.
