# Pi adapter for adversarial-review

Pi discovers skills under `~/.pi/agent/skills/<name>/SKILL.md`. This adapter
symlinks the plugin's shared `skills/` into that location so the same `SKILL.md`
files serve Pi, Claude Code, and Codex without duplication.

## Install

```bash
bash adapters/pi-skill/install.sh
```

Then reload Pi:

```text
/reload
```

Verify:

```bash
ls -la ~/.pi/agent/skills | grep -E 'adversarial|review-all|prompt-optimize'
```

You should see symlinks pointing back to this repo's `skills/` subdirs:

```text
adversarial-plan-review -> /path/to/coding-plugins/adversarial-review/skills/adversarial-plan-review
coding-adversarial-review -> ...
prompt-optimize -> ...
review-all -> ...
```

## Uninstall

```bash
rm ~/.pi/agent/skills/{adversarial-plan-review,coding-adversarial-review,prompt-optimize,review-all}
```

## Why symlinks vs copies

The plugin treats `skills/` as **single source of truth**. Edits in one place
propagate to every host adapter.
