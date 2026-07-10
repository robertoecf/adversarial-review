# Lessons from Codex Companion adversarial review

Source: OpenAI `codex-plugin-cc` adversarial prompt + review output schema
(https://github.com/openai/codex-plugin-cc), adapted for this multi-host skill.

We do **not** copy their JSON-only contract or app-server. We take the critique
discipline that made their adversarial pass sharper than a generic red-team list.

## Adopted

### 1. Operating stance

- Job is to **break confidence** in the change, not to validate it.
- No credit for good intent, partial fixes, or “likely follow-up”.
- Happy-path-only = real weakness.

### 2. Expensive attack surface first

Prioritize failures that are costly, dangerous, or hard to detect:

- auth, permissions, tenant isolation, trust boundaries
- data loss, corruption, duplication, irreversible state
- rollback safety, retries, partial failure, idempotency
- races, ordering, stale state, re-entrancy
- empty/null/timeout/degraded dependency paths
- version skew, schema drift, migration hazards
- observability gaps that hide failure

Security/OWASP still matters; it sits inside this prioritization rather than
as a disconnected checklist dump.

### 3. Finding bar (material only)

Every finding must answer:

1. What can go wrong?
2. Why is this path vulnerable?
3. What is the likely impact?
4. What concrete change reduces the risk?

Exclude: style, naming, low-value cleanup, speculation without evidence.

### 4. Calibration

- Prefer **one strong finding** over several weak ones.
- Do not dilute P0/P1 with filler.
- If it looks safe, say so and return **no findings**.

### 5. Grounding

- Every finding must be defensible from provided context or tool output.
- Do not invent files, lines, attack chains, or runtime behavior.
- Mark inference explicitly; keep confidence honest.

### 6. Steerable focus

User focus text weights the review, but material issues outside focus still
ship. Focus is a priority hint, not a blindfold.

### 7. Terse ship/no-ship summary

Opening summary is a ship assessment, not a neutral recap.

## Kept from our skill (do not drop)

- Cross-host principle: partner reviews, never the host alone silently
- Classification: plan / code / prompt
- Cross-validation tags: `[cross-validated]` / `[external-only]` / `[host-only]`
- P0–P3 severity + origin tags
- Explicit **DEGRADED MODE** banner
- Prompt review stays host-side (6 dimensions)
- `lib/call-external.sh` as sole external dispatch

## Intentionally not adopted

| Codex Companion piece | Why not |
|---|---|
| JSON-only reviewer output | Multi-host agents synthesize better in markdown; JSON is optional later |
| `approve` / `needs-attention` only | We keep SHIP / REVIEW_NEEDED / DO_NOT_MERGE (+ plan verdicts) |
| App-server / job broker | Out of scope for this skill; belongs to a future companion shell if ever |
| Stop-hook review gate | Burn risk; user-opt-in product decision elsewhere |

## Mapping severity

| Codex schema | This skill |
|---|---|
| critical | P0 |
| high | P1 |
| medium | P2 |
| low | P3 |
| approve (no findings) | SHIP / PROCEED with empty blockers |
| needs-attention | REVIEW_NEEDED or DO_NOT_MERGE / RETHINK by severity |
