#!/usr/bin/env bash
# call-external.sh - call the OPPOSITE agent for adversarial review.
#
# Cross-host principle: "the partner reviews, never the host"
#   host=claude -> artifact-dependent (user decision 2026-07-11):
#     code/diff (default): grok first, then codex Luna max, then pi model chain.
#       Rationale: the diff under review is normally Codex-authored, so Codex
#       reviewing it would be same-family; Grok keeps the cross-family property.
#     plan: codex Luna max first, then grok, then pi model chain.
#       Rationale: plans are architect(Claude)-authored, so Codex IS the
#       cross-family reviewer there.
#   host=codex  -> external=pi xai-oauth/grok-4.5 with xhigh thinking, then pi fallbacks, then claude, then direct xAI
#   host=grok   -> external=codex Luna max, then claude, then non-xAI pi model chain
#   host=pi     -> external=codex Luna max, then claude, then grok (never pi itself)
#
# Stdin:  the prompt to send to the external reviewer (multi-line OK)
# Stdout: external reviewer's analysis in markdown
# Stderr: operational logs (which external was used, latency, fallback chain)
# Exit:
#   0   external reviewer succeeded
#   2   degraded mode - all externals failed, host-self analysis with banner
#   1   error (recursion detected, missing input, etc.)
#
# Env vars consumed:
#   ADVERSARIAL_REVIEW_HOST          override host detection (passed to detect-host.sh)
#   ADVERSARIAL_REVIEW_ARTIFACT      what is being reviewed: "code" (default) or "plan";
#                                    only affects partner order for host=claude
#   ADVERSARIAL_REVIEW_DEPTH         anti-recursion counter; refuse if >= 1
#   ADVERSARIAL_REVIEW_TIMEOUT       seconds; default 300
#   ADVERSARIAL_REVIEW_FORCE_DEGRADED  if "1", skip externals and go straight to degraded
#                                      (for non-destructive smoke tests)
#   ADVERSARIAL_REVIEW_GROK_MODELS     Comma-separated direct-xAI model chain;
#                                      default grok-4.5
#   ADVERSARIAL_REVIEW_GROK_MODEL      Back-compat single direct-xAI model override
#   ADVERSARIAL_REVIEW_GROK_EFFORT     Grok CLI reasoning effort; default high
#   ADVERSARIAL_REVIEW_PI_MODEL        Back-compat single Pi model id override
#   ADVERSARIAL_REVIEW_PI_MODELS       Comma-separated Pi model chain
#   ADVERSARIAL_REVIEW_PI_THINKING     Pi --thinking level for the first explicit model without a :level suffix; default xhigh
#   ADVERSARIAL_REVIEW_ANTIGRAVITY_CMD Antigravity CLI command; default agy
#   ADVERSARIAL_REVIEW_ANTIGRAVITY_MODELS Comma-separated quality-first model ladder
#
# This script is HOST-AGNOSTIC: detects host at runtime, picks the partner.

set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT="${ADVERSARIAL_REVIEW_TIMEOUT:-300}"
DEPTH="${ADVERSARIAL_REVIEW_DEPTH:-0}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/adversarial-review"

if ! mkdir -p "$LOG_DIR"; then
  printf '[call-external] ERROR: cannot create log directory: %s\n' "$LOG_DIR" >&2
  exit 1
fi
chmod 700 "$LOG_DIR" 2>/dev/null || true

log() { printf '[call-external] %s\n' "$*" >&2; }

run_with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    log "WARN: timeout(1) not found; running without wall-clock cap"
    "$@"
  fi
}

run_and_emit_on_success() {
  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/call-external-output.XXXXXX")" || return 1
  if "$@" >"$output_file"; then
    cat "$output_file"
    rm -f "$output_file"
    return 0
  fi
  rm -f "$output_file"
  return 1
}

call_grok() {
  local models_csv="${ADVERSARIAL_REVIEW_GROK_MODELS:-${ADVERSARIAL_REVIEW_GROK_MODEL:-grok-4.5}}"
  local default_effort
  if [ "${ADVERSARIAL_REVIEW_GROK_EFFORT+x}" = "x" ]; then
    default_effort="$ADVERSARIAL_REVIEW_GROK_EFFORT"
  else
    default_effort="high"
  fi
  if ! command -v grok >/dev/null 2>&1; then
    return 1
  fi

  local catalog=""
  local catalog_available=0
  if catalog="$(run_with_timeout "$TIMEOUT" grok models 2>>"$LOG_DIR/grok.err")"; then
    catalog_available=1
  else
    log "WARN: grok models failed; trying configured direct-xAI chain"
  fi

  local IFS=,
  local models
  read -r -a models <<< "$models_csv"
  local model
  for model in "${models[@]}"; do
    model="${model#"${model%%[![:space:]]*}"}"
    model="${model%"${model##*[![:space:]]}"}"
    [ -n "$model" ] || continue

    if [ "$catalog_available" -eq 1 ] && ! printf '%s\n' "$catalog" \
      | awk -v wanted="$model" '{ for (i = 1; i <= NF; i++) { token = $i; gsub(/^\*/, "", token); gsub(/[()]/, "", token); if (token == wanted) found = 1 } } END { exit !found }'; then
      log "direct-xAI model unavailable, skipping: ${model}"
      continue
    fi

    local effort="$default_effort"
    if [ -n "$effort" ]; then
      log "calling: grok -p -m ${model} --reasoning-effort ${effort} --yolo (DEPTH=$((DEPTH+1)))"
      if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
        grok -p "$prompt" -m "$model" --reasoning-effort "$effort" --yolo --output-format plain --no-auto-update --cwd "${PWD}" \
        2>>"$LOG_DIR/grok.err" </dev/null; then
        return 0
      fi
    else
      log "calling: grok -p -m ${model} --yolo (reasoning effort omitted, DEPTH=$((DEPTH+1)))"
      if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
        grok -p "$prompt" -m "$model" --yolo --output-format plain --no-auto-update --cwd "${PWD}" \
        2>>"$LOG_DIR/grok.err" </dev/null; then
        return 0
      fi
    fi
    log "direct-xAI model failed: ${model}"
  done
  return 1
}

call_pi() {
  if ! command -v pi >/dev/null 2>&1; then
    return 1
  fi

  local models_csv="${ADVERSARIAL_REVIEW_PI_MODELS:-${ADVERSARIAL_REVIEW_PI_MODEL:-xai-oauth/grok-4.5,opencode-go/deepseek-v4-flash:xhigh,moonshotai/kimi-k3:xhigh}}"
  local pi_thinking
  if [ "${ADVERSARIAL_REVIEW_PI_THINKING+x}" = "x" ]; then
    pi_thinking="$ADVERSARIAL_REVIEW_PI_THINKING"
  else
    pi_thinking="xhigh"
  fi
  local IFS=,
  local models
  read -r -a models <<< "$models_csv"

  # Keep the caller's PWD. Pi's opencode-go key may be a Doppler reference,
  # and Doppler scope is path-based on this machine.
  local model
  local model_idx=0
  for model in "${models[@]}"; do
    model="${model#"${model%%[![:space:]]*}"}"
    model="${model%"${model##*[![:space:]]}"}"
    [ -n "$model" ] || continue
    local is_first_model=0
    if [ "$model_idx" -eq 0 ]; then
      is_first_model=1
    fi
    model_idx=$((model_idx + 1))

    if [ "$model" = "default" ] || [ "$model" = "pi-default" ] || [ "$model" = "__default__" ]; then
      log "calling: pi -p --mode text --no-tools --no-session (configured default override, DEPTH=$((DEPTH+1)))"
      if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
        pi -p --mode text --no-tools --no-session "$prompt" \
        2>>"$LOG_DIR/pi.err" </dev/null; then
        return 0
      fi
      log "pi model failed: configured default override"
      continue
    fi

    case "$model" in
      *:off|*:minimal|*:low|*:medium|*:high|*:xhigh)
        log "calling: pi -p --mode text --no-tools --no-session --model ${model} (DEPTH=$((DEPTH+1)))"
        if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
          pi -p --mode text --no-tools --no-session --model "$model" "$prompt" \
          2>>"$LOG_DIR/pi.err" </dev/null; then
          return 0
        fi
        ;;
      *)
        if [ "$is_first_model" -eq 1 ] && [ -n "$pi_thinking" ]; then
          log "calling: pi -p --mode text --no-tools --no-session --model ${model} --thinking ${pi_thinking} (DEPTH=$((DEPTH+1)))"
          if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
            pi -p --mode text --no-tools --no-session --model "$model" --thinking "$pi_thinking" "$prompt" \
            2>>"$LOG_DIR/pi.err" </dev/null; then
            return 0
          fi
        else
          log "calling: pi -p --mode text --no-tools --no-session --model ${model} (DEPTH=$((DEPTH+1)))"
          if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
            pi -p --mode text --no-tools --no-session --model "$model" "$prompt" \
            2>>"$LOG_DIR/pi.err" </dev/null; then
            return 0
          fi
        fi
        ;;
    esac
    log "pi model failed: ${model}"
  done
  return 1
}

call_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    return 1
  fi
  log "calling: codex exec -m gpt-5.6-luna -c model_reasoning_effort=max --sandbox read-only (DEPTH=$((DEPTH+1)))"
  run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
    codex exec -m gpt-5.6-luna -c model_reasoning_effort=max --sandbox read-only --skip-git-repo-check "$prompt" \
    2>>"$LOG_DIR/codex.err" </dev/null
}

call_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    return 1
  fi
  log "calling: claude -p --model opus --effort xhigh --bare --tools <none> (DEPTH=$((DEPTH+1)))"
  run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
    claude -p --model opus --effort xhigh --bare --tools "" --dangerously-skip-permissions "$prompt" \
    2>>"$LOG_DIR/claude.err" </dev/null
}

find_antigravity_cmd() {
  if [ -n "${ADVERSARIAL_REVIEW_ANTIGRAVITY_CMD:-}" ]; then
    printf '%s\n' "$ADVERSARIAL_REVIEW_ANTIGRAVITY_CMD"
    return 0
  fi
  if command -v agy >/dev/null 2>&1; then
    command -v agy
    return 0
  fi
  if [ -x "$HOME/.local/bin/agy" ]; then
    printf '%s\n' "$HOME/.local/bin/agy"
    return 0
  fi
  if command -v antigravity >/dev/null 2>&1; then
    command -v antigravity
    return 0
  fi
  return 1
}

call_antigravity() {
  local cmd
  cmd="$(find_antigravity_cmd)" || return 1

  local models_csv="${ADVERSARIAL_REVIEW_ANTIGRAVITY_MODELS:-gemini-3.6-flash-high,claude-opus-4-6-thinking,gemini-3.1-pro-high,claude-sonnet-4-6,gpt-oss-120b-medium,gemini-3.6-flash-medium}"
  local catalog=""
  local catalog_available=0
  if catalog="$(run_with_timeout "$TIMEOUT" "$cmd" models 2>>"$LOG_DIR/antigravity.err")"; then
    catalog_available=1
  else
    log "WARN: Antigravity model discovery failed; trying configured ladder"
  fi

  local IFS=,
  local models
  read -r -a models <<< "$models_csv"
  local model
  for model in "${models[@]}"; do
    model="${model#"${model%%[![:space:]]*}"}"
    model="${model%"${model##*[![:space:]]}"}"
    [ -n "$model" ] || continue

    if [ "$catalog_available" -eq 1 ] && ! printf '%s\n' "$catalog" | grep -Fxq "$model"; then
      log "Antigravity model unavailable, skipping: ${model}"
      continue
    fi

    log "calling: ${cmd} -p <prompt> --model ${model} --sandbox (DEPTH=$((DEPTH+1)))"
    if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
      "$cmd" -p "$prompt" --print-timeout "${TIMEOUT}s" --model "$model" --sandbox \
      2>>"$LOG_DIR/antigravity.err" </dev/null; then
      return 0
    fi
    log "Antigravity model failed or quota unavailable: ${model}"
  done
  return 1
}

# 1. Anti-recursion: if a parent already invoked us, refuse.
if [ "$DEPTH" -ge 1 ]; then
  log "ERROR: ADVERSARIAL_REVIEW_DEPTH=$DEPTH (>=1) - recursion detected, refusing"
  log "       chain: a parent invocation is already running adversarial review"
  exit 1
fi

# 2. Read prompt from stdin
prompt="$(cat)"
if [ -z "$prompt" ]; then
  log "ERROR: empty prompt on stdin"
  exit 1
fi

# 3. Forced-degraded short-circuit (non-destructive smoke test)
if [ "${ADVERSARIAL_REVIEW_FORCE_DEGRADED:-}" = "1" ]; then
  log "ADVERSARIAL_REVIEW_FORCE_DEGRADED=1 - skipping externals, emitting degraded banner"
  printf '⚠️  DEGRADED MODE - externals skipped (FORCE_DEGRADED=1)\n\n'
  printf 'Host-self analysis (the host is reviewing its own work - violates cross-host principle):\n\n'
  printf '%s\n' "$prompt"
  exit 2
fi

# 4. Detect host
if ! HOST="$(bash "$LIB_DIR/detect-host.sh")"; then
  HOST=unknown
fi
log "host=$HOST  depth=$DEPTH  timeout=${TIMEOUT}s"

# 5. Route to opposite partner
case "$HOST" in
  claude)
    ARTIFACT="${ADVERSARIAL_REVIEW_ARTIFACT:-code}"
    if [ "$ARTIFACT" = "plan" ]; then
      # Plan is architect(Claude)-authored: Codex is the cross-family reviewer.
      log "artifact=plan - codex first, then grok"
      if call_codex; then exit 0; fi
      log "codex exec failed; trying grok"
      if call_grok; then exit 0; fi
      log "grok failed; trying pi"
    else
      # Code/diff is normally Codex-authored: Grok keeps the review cross-family.
      log "artifact=${ARTIFACT} - grok first, then codex"
      if call_grok; then exit 0; fi
      log "grok failed; trying codex"
      if call_codex; then exit 0; fi
      log "codex exec failed; trying pi"
    fi
    if call_pi; then exit 0; fi
    log "pi failed; trying Antigravity model ladder"
    ;;
  codex)
    if call_pi; then exit 0; fi
    log "pi failed; trying claude"
    if call_claude; then exit 0; fi
    log "claude -p failed; trying grok"
    if call_grok; then exit 0; fi
    log "grok failed; trying Antigravity model ladder"
    ;;
  grok)
    if call_codex; then exit 0; fi
    log "codex exec failed; trying claude"
    if call_claude; then exit 0; fi
    log "claude -p failed; trying non-xAI pi chain"
    if ADVERSARIAL_REVIEW_PI_MODELS="opencode-go/deepseek-v4-flash:xhigh,moonshotai/kimi-k3:xhigh" call_pi; then exit 0; fi
    log "non-xAI pi chain failed; trying Antigravity model ladder"
    ;;
  pi)
    if call_codex; then exit 0; fi
    log "codex exec failed; trying claude"
    if call_claude; then exit 0; fi
    log "claude -p failed; trying grok"
    if call_grok; then exit 0; fi
    log "grok failed; trying Antigravity model ladder"
    ;;
  unknown|*)
    log "host=unknown - set ADVERSARIAL_REVIEW_HOST manually; trying direct xAI, then pi, then Antigravity"
    if call_grok; then exit 0; fi
    log "grok failed; trying pi"
    if call_pi; then exit 0; fi
    log "pi failed; trying Antigravity model ladder"
    ;;
esac

# 6. Quality-first Antigravity CLI ladder (fallback for both directions)
if call_antigravity; then
  exit 0
fi
log "Antigravity model ladder unavailable or failed"

# 7. Degraded mode - host-self analysis with explicit banner
log "DEGRADED MODE - no external partner available; host will self-review"
printf '⚠️  DEGRADED MODE - Cross-host principle violated\n\n'
printf 'No external partner (Codex / Claude / Grok / Pi / Antigravity) was reachable. '
printf 'The host is reviewing its own work, which the principle forbids - '
printf 'output below is single-perspective and may have blind spots.\n\n'
printf '%s\n%s\n' '-- original prompt --' "$prompt"
exit 2
