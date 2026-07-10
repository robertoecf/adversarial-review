# CLAUDE.md - Claude Code directives

## Plugin: adversarial-review v0.7.0

Cross-host adversarial review for coding workflows. Detects which agent host
the SKILL.md is running under and routes review to the OTHER agent: Codex if
the host is Claude Code, Pi xAI OAuth Grok 4.5 with xhigh thinking first if the host is Codex,
Codex/Claude if the host is Grok Build CLI, with Claude, Grok 4.5 xhigh, and the
Pi model chain as secondary externals. Falls back to Gemini via
non-interactive Antigravity CLI, then degraded host-self with explicit warning.

v0.7 hardens critique discipline (Codex Companion lessons): break-confidence
stance, expensive attack surface first, material-only finding bar, steerable
focus, terse ship/no-ship summary. See `references/codex-lessons.md`.

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
- **Grok CLI** is pinned to `grok-4.5` with `--reasoning-effort xhigh` for the Grok leg.
  Preferred auth is inherited `XAI_API_KEY`; `grok models` should list `grok-4.5`.
  This is direct xAI key auth, not OpenRouter.
- **Pi model chain** uses `pi -p --mode text --no-tools --model` for the
  default explicit chain. Run it from the caller's repo/worktree root. Default
  order: `xai-oauth/grok-4.5` with `--thinking xhigh`, `opencode-go/glm-5.2:high`,
  `moonshotai/kimi-k2.7-code-highspeed`. The Moonshot leg is direct API via
  `MOONSHOT_API_KEY`, not OpenRouter. The `default` token is still accepted as
  an override when the caller wants Pi's configured default. Do not run it from
  `/tmp` when opencode-go keys resolve through Doppler scope.
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

- `/adversarial-review:adversarial-review` - single entry point: classifies the
  input (plan, code, prompt) and runs the matching procedure (plan critique,
  code red-team, or host-side prompt analysis)

In Codex, the same skill is available as `$adversarial-review` after running
`bash adapters/codex-skill/install.sh` (symlinks into `~/.codex/skills/`).

## Plugin dev workflow

- Edit source at `/Users/macbook/repos/skills/plugins/adversarial-review/`
- Reinstall via marketplace:
  ```bash
  claude plugin uninstall adversarial-review 2>/dev/null || true
  claude plugin marketplace add ~/repos/skills/plugins/adversarial-review
  claude plugin install adversarial-review@adversarial-review
  ```
- Reload in current session: `/reload-plugins`
- Skill invocation requires fully qualified name:
  `/adversarial-review:<skill-name>`

## File size discipline

No single file in this plugin should exceed 500 lines.
