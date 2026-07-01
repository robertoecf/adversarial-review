# CLAUDE.md - Claude Code directives

## Plugin: adversarial-review v0.5.0

Cross-host adversarial review for coding workflows. Detects which agent host
the SKILL.md is running under and routes review to the OTHER agent: Codex if
the host is Claude Code, Claude (Opus xhigh) if the host is Codex,
Codex/Claude if the host is Grok Build CLI, with Grok (Composer 2.5) and the
Pi model chain as secondary externals. Falls back to Gemini via
non-interactive Antigravity CLI, then degraded host-self with explicit warning.

## Architecture

- **Single source of truth**: `skills/<name>/SKILL.md`. Same file for both hosts.
- **Cross-host routing** lives in `lib/call-external.sh`. Skills NEVER call
  `codex exec`, `claude -p`, `grok -p`, or `pi -p` directly. They pipe prompts
  into the lib script.
- **Host detection** in `lib/detect-host.sh` (override -> env -> PPID walk).
- **Anti-recursion**: `ADVERSARIAL_REVIEW_DEPTH` env counter incremented at
  each cross-agent hop; refuse on `≥ 1`.
- **Main session does the synthesis.** No haiku Agent courier subagent. The
  agent reading the SKILL.md runs `lib/call-external.sh`, runs its own
  independent analysis, cross-validates, returns unified output.
- **Degraded mode** when all externals fail: stdout banner `⚠️  DEGRADED MODE`,
  exit 2 from `call-external.sh`, surfaced at the top of skill output.

## Critical gotchas

- **`forced_login_method = "chatgpt"`** must be in `~/.codex/config.toml` for
  ChatGPT-account users - without it, `codex exec` returns 404 "Model not
  found gpt-5.4" even though TUI works. See `references/codex-integration.md`.
- **`"skills": "./skills/"`** required in `plugin.json` for Claude Code to
  discover SKILL.md files.
- **Plugin cache** lives at `~/.claude/plugins/cache/` - manually update
  during dev after source changes (or reinstall the plugin).
- **Global gitignore** at `~/.config/git/ignore` blocks `.claude/settings.local.json` -
  use `git add -f` to include it.
- **Codex CLI** needs `--sandbox read-only` for review (we never want writes
  during a critique pass) and `--skip-git-repo-check` since the prompt is the
  unit of review.
- **Pi model chain** uses `pi -p --mode text --no-tools` for `default`, then
  `--model` for explicit fallback models. Run it from the caller's repo/worktree
  root. Default order: Pi default config, `opencode-go/glm-5.2:high`,
  `opencode-go/kimi-k2.7-code`. Do not run it from `/tmp` when opencode-go keys
  resolve through Doppler scope.
- **Gemini fallback** uses Antigravity CLI non-interactively:
  `agy --print --print-timeout "${ADVERSARIAL_REVIEW_TIMEOUT:-300}s" --sandbox`.
  Do not use the standalone `gemini` CLI for this fallback.
- **Long prompts (>~6 kB) can stall Codex backend.** SKILLs should summarize
  rather than paste raw if the input is huge. Verified empirically - a single
  meta-review prompt with a 200+ line plan stalled `codex exec` for 20+ min
  with 0% CPU before being killed.

## Tool preferences

- Use `Read` over `cat` / `head` / `tail`
- Use `Grep` over `grep` / `rg`
- Use `Glob` over `find` / `ls`
- Use the `Bash` tool to invoke `lib/call-external.sh` - that's the only path

## Available skills (slash refs qualified)

- `/adversarial-review:adversarial-plan-review` - pre-implementation plan critique
- `/adversarial-review:coding-adversarial-review` - code/diff red-team
- `/adversarial-review:prompt-optimize` - prompt engineering analysis (single-host, no external)
- `/adversarial-review:review-all` - input classifier; routes to one of the above

In Codex, the same skills are available as `$<skill-name>` after running
`bash adapters/codex-skill/install.sh` (symlinks into `~/.codex/skills/`).

## Plugin dev workflow

- Edit source at `/Users/macbook/repos/coding-plugins/adversarial-review/`
- Reinstall via marketplace:
  ```bash
  claude plugin uninstall adversarial-review 2>/dev/null || true
  claude plugin marketplace add ~/repos/coding-plugins/adversarial-review
  claude plugin install adversarial-review@adversarial-review
  ```
- Reload in current session: `/reload-plugins`
- Skill invocation requires fully qualified name:
  `/adversarial-review:<skill-name>`

## File size discipline

No single file in this plugin should exceed 500 lines.
