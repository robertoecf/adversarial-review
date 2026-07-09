#!/usr/bin/env bash
# install.sh — install adversarial-review skills into Codex's skill directory.
#
# Codex discovers skills at ~/.codex/skills/<name>/SKILL.md. This script
# symlinks each skill from the plugin's shared skills/ directory into Codex's
# skill dir, so updates to skills/ in this repo propagate without re-copying.
#
# Idempotent — safe to re-run.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/skills"
CODEX_SKILLS_DIR="$HOME/.codex/skills"

if [ ! -d "$SKILLS_DIR" ]; then
  echo "ERROR: $SKILLS_DIR not found — is this script being run from the plugin tree?" >&2
  exit 1
fi

mkdir -p "$CODEX_SKILLS_DIR"

legacy_removed=0
legacy_skipped=0
legacy_skills=(
  adversarial-plan-review
  coding-adversarial-review
  prompt-optimize
  review-all
)

for legacy_name in "${legacy_skills[@]}"; do
  legacy_target="$CODEX_SKILLS_DIR/$legacy_name"
  [ -e "$legacy_target" ] || [ -L "$legacy_target" ] || continue

  if [ -L "$legacy_target" ]; then
    current="$(readlink "$legacy_target")"
    case "$current" in
      "$SKILLS_DIR/$legacy_name"|"$SKILLS_DIR/$legacy_name/"|*/plugins/adversarial-review/skills/"$legacy_name"|*/plugins/adversarial-review/skills/"$legacy_name"/)
        rm -f "$legacy_target"
        printf '  - %s (removed legacy symlink)\n' "$legacy_name"
        legacy_removed=$((legacy_removed+1))
        ;;
      *)
        printf '  ⚠ %s legacy name exists but points elsewhere (%s) — leaving untouched\n' "$legacy_name" "$current" >&2
        legacy_skipped=$((legacy_skipped+1))
        ;;
    esac
  else
    printf '  ⚠ %s legacy name exists as a real file/dir — leaving untouched\n' "$legacy_name" >&2
    legacy_skipped=$((legacy_skipped+1))
  fi
done

count_new=0
count_replaced=0
count_kept=0

for skill_dir in "$SKILLS_DIR"/*/; do
  skill_name="$(basename "$skill_dir")"
  target="$CODEX_SKILLS_DIR/$skill_name"

  if [ -L "$target" ]; then
    # Already a symlink — check if it points to our source
    current="$(readlink "$target")"
    if [ "$current" = "$skill_dir" ] || [ "$current" = "${skill_dir%/}" ]; then
      printf '  ✓ %s (already linked, kept)\n' "$skill_name"
      count_kept=$((count_kept+1))
      continue
    fi
    printf '  ↻ %s (replacing stale symlink → %s)\n' "$skill_name" "$current"
    rm -f "$target"
    count_replaced=$((count_replaced+1))
  elif [ -e "$target" ]; then
    printf '  ⚠ %s exists as a real file/dir at %s — skipping (resolve manually)\n' "$skill_name" "$target" >&2
    continue
  else
    count_new=$((count_new+1))
  fi

  ln -s "${skill_dir%/}" "$target"
  printf '  → %s\n' "$skill_name"
done

printf '\nInstalled to %s\n' "$CODEX_SKILLS_DIR"
printf 'new=%d replaced=%d kept=%d legacy_removed=%d legacy_skipped=%d\n' "$count_new" "$count_replaced" "$count_kept" "$legacy_removed" "$legacy_skipped"
printf '\nVerify: ls -la %s\n' "$CODEX_SKILLS_DIR"
printf 'Use in Codex: "$<skill-name>" prefix in prompts (e.g. "$adversarial-review please review my plan")\n'
