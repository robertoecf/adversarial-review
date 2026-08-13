# CLAUDE.md - Claude Code directives

## Plugin: adversarial-review v0.9.4

Cross-host adversarial review for coding workflows. Detects which agent host
the SKILL.md is running under and routes review to another model family. Claude
code reviews use direct-xAI Grok 4.5 first, while Claude plan reviews use Codex
Luna first. Codex-host routing is author-aware: Codex-authored artifacts use the
Pi Grok chain first, while Grok-authored artifacts use Codex Luna first. Grok
and Pi hosts use Codex first. Each
route has explicit secondary providers, then a quality-first Antigravity
Claude, Gemini, and GPT ladder, then degraded host-self with explicit warning.

v0.9.4 adds author-aware Codex routing through `ADVERSARIAL_REVIEW_AUTHOR`
and changes the Antigravity default to Gemini 3.7 Flash High. It also accepts
Antigravity's tabular model catalog and falls through on empty provider output.
The previous
release replaced the OpenCode Go fallback with DeepSeek V4 Flash xhigh and
kept the Luna reviewer at max effort. v0.9.1 originally made Gemini 3.6 Flash
High the first Antigravity candidate. Routing
policy 2026-07-23 makes Grok 4.5, xAI's frontier model, the sole direct-xAI
model at high effort. v0.9.0 routes direct Moonshot review to Kimi K3 xhigh
and adds quota-aware Antigravity failover across providers. v0.8.2 pinned every Codex reviewer
invocation to GPT-5.6 Luna with read-only sandboxing.
v0.8.1 added a mandatory simplicity
counterfactual to plan and code reviews:
hold required behavior and safety fixed, then challenge YAGNI, false seams,
duplicate ownership, missed in-repo reuse, and unnecessary machinery. Existing
canonical Effect implementations count as reuse evidence; Effect and lower LOC
are never goals by themselves.

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
  during a critique pass), `-m gpt-5.6-luna`,
  `-c model_reasoning_effort=max`, and `--skip-git-repo-check` since the
  prompt is the unit of review.
- **Direct xAI through Grok CLI** uses `grok-4.5` with
  `--reasoning-effort high`. Grok 4.5 is xAI's frontier model, and high is the
  largest effort the current Grok CLI accepts.
  The script checks `grok models` and skips unavailable entries. Preferred auth
  is inherited
  `XAI_API_KEY`; this is not OpenRouter.
- **Pi model chain** uses `pi -p --mode text --no-tools --model` for the
  default explicit chain. Run it from the caller's repo/worktree root. Default
  order: `xai-oauth/grok-4.5` with `--thinking xhigh`, `opencode-go/deepseek-v4-flash:xhigh`,
  `moonshotai/kimi-k3:xhigh`. The Moonshot leg is direct API via
  `MOONSHOT_API_KEY`, not OpenRouter. The `default` token is still accepted as
  an override when the caller wants Pi's configured default. Do not run it from
  `/tmp` when opencode-go keys resolve through Doppler scope.
- **Antigravity fallback** runs `agy models`, filters a quality-first ladder,
  and tries available Claude, Gemini, and GPT models in order. Each call pins
  `--model`; quota or call failure advances to the next candidate. Do not use
  the standalone `gemini` CLI for this fallback.
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
