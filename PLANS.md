# Plans: adversarial-review upgrade → pi-companion

## Plan 1 — adversarial-review v0.7 (this plugin)

**Goal:** harden the existing cross-host skill with Codex Companion lessons, without adding a second product surface.

**Source of truth:** `~/repos/skills/plugins/adversarial-review`  
**Live installs:** Claude plugin cache / marketplace path, `~/.codex/skills/adversarial-review` (adapter), `~/.pi/agent/skills/adversarial-review` (symlink adapter)

### In scope

1. **Code-review prompt upgrade** (Codex-inspired):
   - operating stance: break confidence, do not validate
   - expensive attack surface first (auth, data loss, rollback, races, idempotency, observability)
   - finding bar: only material findings; 4-question test
   - calibration: prefer one strong finding over many weak ones
   - grounding: no invented files/lines/paths
   - steerable **focus text**
2. **Plan-review prompt upgrade** with the same stance/calibration (plan-shaped checklist kept).
3. **Output standards** tightened: ship/no-ship summary, material-only bar, confidence + origin tags.
4. **Optional JSON shape** documented as reference (markdown remains default for multi-host agents).
5. Version bump **0.6.1 → 0.7.0** across `plugin.json`, `SKILL.md`, `CLAUDE.md`, `README.md`.
6. Re-run Pi/Codex adapters so live installs see the change.

### Out of scope (Plan 1)

- job store / status / cancel
- `pi companion` CLI
- review gate / transfer
- reimplementing adversarial inside a new package

### Done when

- [x] SKILL.md v0.7.0 with stance/attack-surface/finding-bar/focus
- [x] `references/output-standards.md` updated
- [x] `references/codex-lessons.md` captures what we took from Codex Companion
- [x] README / AGENTS / CLAUDE / plugin.json / marketplace.json version aligned
- [x] adapters reinstalled (pi + codex) — symlinks already pointed at source
- [x] degraded + recursion smoke still pass (exit 2 / exit 1)

---

## Plan 2 — pi-companion (after Plan 1)

**Goal:** thin multi-host guest port for Pi, Codex-shaped routes, modules optional at setup. Adversarial is opt-in and **reuses** this plugin — never reimplements it.

### Core (v1)

```text
pi companion setup [--enable adversarial-review] [--enable review] [--enable rescue]
pi companion review [--base <ref>] [--soft] [focus...]     # soft = non-adversarial
pi companion adversarial-review [--base <ref>] [focus...]  # requires module
pi companion rescue <task...>                              # optional module
```

### Deferred

- transfer, review gate, app-server, job framework (host background first)

### Done when (v0.1 scaffold)

- [x] package layout + CLI entrypoint → `plugins/pi-companion`
- [x] setup module toggles (`~/.pi/companion/config.json`)
- [x] adversarial module invokes this skill via `pi -p --skill`
- [x] Claude / Codex / Cursor thin adapter recipes
- [x] docs: README install + examples

Plan 1 complete; Plan 2 scaffold shipped in sibling package.
