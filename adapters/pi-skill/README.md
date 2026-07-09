# Pi adapter for adversarial-review

Pi discovers skills under `~/.pi/agent/skills/<name>/SKILL.md`. This adapter
symlinks the plugin's shared `skills/` into that location so the same `SKILL.md`
files serve Pi, Claude Code, and Codex without duplication.

## Install

```bash
bash adapters/pi-skill/install.sh
```

The installer removes legacy symlinks from the pre-0.6 split skills when they
point back to this plugin.

Then reload Pi:

```text
/reload
```

Verify:

```bash
ls -la ~/.pi/agent/skills | grep adversarial
```

You should see a symlink pointing back to this repo's `skills/` subdir:

```text
adversarial-review -> /path/to/skills/plugins/adversarial-review/skills/adversarial-review
```

## Uninstall

```bash
rm ~/.pi/agent/skills/adversarial-review
```

## Why symlinks vs copies

The plugin treats `skills/` as **single source of truth**. Edits in one place
propagate to every host adapter.
