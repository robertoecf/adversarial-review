# AGENTS.md: review agent guidelines (host-agnostic)

## Plugin architecture

This plugin implements a single principle:

> **The partner reviews, never the host.**

For every review (plan, code, or prompt — all through the single `adversarial-review` skill):

- The agent reading the SKILL.md is the **host**.
- The host **must not** review the host's own work.
- The host runs `lib/call-external.sh` to delegate the heavy critique to the
  OTHER agent (the **partner**).
- The host then runs its own independent analysis and **cross-validates**
  against the partner's output, tagging findings as `[cross-validated]`,
  `[external-only]`, or `[host-only]`.

There is **no haiku courier subagent** in this version. The host (main
session) does both the external dispatch and the synthesis. Removed in the
0.5.0 refactor: the courier added complexity (model inconsistency across
files, blocking-vs-non-blocking ambiguity) without proportionate value.

## Cross-host routing

| Detected host | Partner                              |
|---------------|--------------------------------------|
| `claude`      | Code: direct-xAI Grok 4.5, Codex Luna max, Pi. Plan: Codex Luna max, direct-xAI Grok 4.5, Pi. Then Antigravity |
| `codex`       | Author-aware: Codex-authored work goes to Pi Grok first; Grok-authored work goes to Codex Luna max first. Omitted plan author infers Codex; omitted code author infers Grok |
| `grok`        | Codex GPT-5.6 Luna max, then Claude, non-xAI Pi (DeepSeek then Kimi, never Grok), and the Antigravity ladder |
| `pi`          | Codex GPT-5.6 Luna max, then Claude, direct xAI, and the Antigravity ladder |
| `unknown`     | Direct xAI, then Pi, then the Antigravity ladder |

Detection happens at every invocation via `lib/detect-host.sh`. See
`references/host-detection.md` for the priority order and the env-leak
asymmetry that drives "Codex env first, Claude env second".

Codex-host callers should set `ADVERSARIAL_REVIEW_AUTHOR` to `codex`, `grok`,
`claude`, `pi`, `user`, or `unknown`. Aliases `sol`, `openai`, `xai`, and
`anthropic` are accepted case-insensitively. Unknown authors use Luna first,
then Claude and the non-xAI Pi chain.

## Anti-recursion contract

`lib/call-external.sh` reads `ADVERSARIAL_REVIEW_DEPTH` (default `0`). If
it sees `≥ 1`, it refuses with exit `1`. Before invoking the partner, it
sets `ADVERSARIAL_REVIEW_DEPTH=1` in the partner's env. So if a launched
partner ever re-triggers this skill, the guard fires. Never disable.

## Critique discipline (v0.8.1+)

- **Stance**: break confidence; do not validate. No credit for intent or likely follow-up.
- **Attack surface**: prioritize expensive failures (auth/trust, data loss, rollback/idempotency, races, degraded deps, migrations, observability gaps).
- **Finding bar**: material only — what fails, why vulnerable, impact, concrete fix. Prefer one strong finding over many weak ones. Clean review with zero findings is valid.
- **Over-engineering**: every plan/code review runs a simplicity counterfactual with required behavior and safety held fixed. Challenge YAGNI, false seams, duplicate ownership, and missed in-repo reuse, including canonical Effect implementations. LOC or framework taste alone is never a finding. An OE finding requires a path/line or plan-section anchor, cited evidence plus material failure/cost/risk, and a simpler alternative that preserves behavior and safety; see `references/output-standards.md`.
- **Focus**: user focus weights the pass; other material issues still report.
- **Summary**: terse ship/no-ship first (≤200 tokens), not a neutral recap.
- Details: `references/codex-lessons.md`, `references/output-standards.md`.

## Output integrity (for synthesis by the host)

Every finding in the final output MUST include:

1. **Severity**: P0 (critical) / P1 (high) / P2 (medium) / P3 (low)
2. **Evidence**: direct quote, file:line reference, or concrete scenario
3. **Impact**: user/data/security/ops consequence
4. **Recommendation**: specific, actionable fix
5. **Confidence**: high | medium | low
6. **Origin tag**: `[cross-validated]` / `[external-only]` / `[host-only]`
   (from the cross-validation step)

Do not invent files, lines, or attack chains. Mark inferences.

## Severity scale

| Level | Meaning                                                | Action                       |
|-------|--------------------------------------------------------|------------------------------|
| P0    | Critical: exploitable, data loss, security breach      | Must fix before merge/deploy |
| P1    | High: significant risk, likely failure mode            | Should fix in this iteration |
| P2    | Medium: material quality/reliability, limited blast    | Fix when convenient          |
| P3    | Low: only if still material — not style dump           | Optional improvement         |

## Fallback chain

See `references/fallback-chain.md`. Order: primary partner -> secondary CLIs
-> quality-first Antigravity ladder -> DEGRADED. **The DEGRADED mode emits an explicit banner** in stdout and
returns exit 2 from `call-external.sh` so the SKILL knows to surface it to
the user.

## Honesty rules

- When a review is clean, say so. Do not manufacture findings.
- When uncertain about severity, use confidence tags.
- When input is ambiguous, ask; don't guess.
- When degraded mode triggers, **always show the banner**. Silent self-review
  is the failure mode this plugin was designed to prevent.

## What this plugin does NOT cover

- **Live multi-turn dialog with the partner.** The call is one-shot:
  prompt in, analysis out. If you need iteration, the host asks the user;
  the user asks the partner directly via the partner's interactive UI.
- **Approval workflows.** This plugin produces critiques, not approvals.
  Merge / ship decisions remain the user's.
- **State persistence across calls.** Each `lib/call-external.sh` invocation
  is independent. State that needs to persist lives in host memory
  (`~/.claude/projects/<cwd>/memory/` or `~/.codex/memories/`).
