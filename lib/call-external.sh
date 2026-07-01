#!/usr/bin/env bash
# call-external.sh - call the OPPOSITE agent for adversarial review.
#
# Cross-host principle: "the partner reviews, never the host"
#   host=claude -> external=codex, then grok, then pi model chain
#   host=codex  -> external=claude, then grok, then pi model chain
#   host=grok   -> external=codex, then claude, then pi model chain
#   host=pi     -> external=codex, then claude, then grok (never pi itself)
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
#   ADVERSARIAL_REVIEW_DEPTH         anti-recursion counter; refuse if >= 1
#   ADVERSARIAL_REVIEW_TIMEOUT       seconds; default 300
#   ADVERSARIAL_REVIEW_FORCE_DEGRADED  if "1", skip externals and go straight to degraded
#                                      (for non-destructive smoke tests)
#   ADVERSARIAL_REVIEW_GROK_MODEL      Grok Build CLI model id; default grok-composer-2.5-fast
#   ADVERSARIAL_REVIEW_PI_MODEL        Back-compat single Pi model id override
#   ADVERSARIAL_REVIEW_PI_MODELS       Comma-separated Pi model chain
#   ADVERSARIAL_REVIEW_ANTIGRAVITY_CMD Antigravity CLI command; default agy
#
# This script is HOST-AGNOSTIC: detects host at runtime, picks the partner.

set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT="${ADVERSARIAL_REVIEW_TIMEOUT:-300}"
DEPTH="${ADVERSARIAL_REVIEW_DEPTH:-0}"

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

call_grok() {
  local model="${ADVERSARIAL_REVIEW_GROK_MODEL:-grok-composer-2.5-fast}"
  if ! command -v grok >/dev/null 2>&1; then
    return 1
  fi
  log "calling: grok -p -m ${model} --yolo (DEPTH=$((DEPTH+1)))"
  ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
    run_with_timeout "$TIMEOUT" grok -p "$prompt" -m "$model" --yolo --output-format plain --no-auto-update --cwd "${PWD}" \
    2>>/tmp/call-external-grok.err
}

call_pi() {
  if ! command -v pi >/dev/null 2>&1; then
    return 1
  fi

  local models_csv="${ADVERSARIAL_REVIEW_PI_MODELS:-${ADVERSARIAL_REVIEW_PI_MODEL:-default,opencode-go/glm-5.2:high,moonshotai/kimi-k2.7-code-highspeed}}"
  local IFS=,
  local models
  read -r -a models <<< "$models_csv"

  # Keep the caller's PWD. Pi's opencode-go key may be a Doppler reference,
  # and Doppler scope is path-based on this machine.
  local model
  for model in "${models[@]}"; do
    model="${model#"${model%%[![:space:]]*}"}"
    model="${model%"${model##*[![:space:]]}"}"
    [ -n "$model" ] || continue

    if [ "$model" = "default" ] || [ "$model" = "pi-default" ] || [ "$model" = "__default__" ]; then
      log "calling: pi -p --mode text --no-tools (default config, DEPTH=$((DEPTH+1)))"
      if ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
        run_with_timeout "$TIMEOUT" pi -p --mode text --no-tools "$prompt" \
        2>>/tmp/call-external-pi.err; then
        return 0
      fi
      log "pi model failed: default config"
      continue
    fi

    log "calling: pi -p --mode text --no-tools --model ${model} (DEPTH=$((DEPTH+1)))"
    if ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
      run_with_timeout "$TIMEOUT" pi -p --mode text --no-tools --model "$model" "$prompt" \
      2>>/tmp/call-external-pi.err; then
      return 0
    fi
    log "pi model failed: ${model}"
  done
  return 1
}

call_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    return 1
  fi
  log "calling: codex exec --sandbox read-only (DEPTH=$((DEPTH+1)))"
  ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
    run_with_timeout "$TIMEOUT" codex exec --sandbox read-only --skip-git-repo-check "$prompt" \
    2>>/tmp/call-external-codex.err
}

call_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    return 1
  fi
  log "calling: claude -p --model opus --effort xhigh (DEPTH=$((DEPTH+1)))"
  ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
    run_with_timeout "$TIMEOUT" claude -p --model opus --effort xhigh --dangerously-skip-permissions "$prompt" \
    2>>/tmp/call-external-claude.err
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

call_antigravity_gemini() {
  local cmd
  cmd="$(find_antigravity_cmd)" || return 1

  log "calling: ${cmd} --print --sandbox (Gemini via Antigravity, DEPTH=$((DEPTH+1)))"
  ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
    run_with_timeout "$TIMEOUT" "$cmd" --print --print-timeout "${TIMEOUT}s" --sandbox "$prompt" \
    2>>/tmp/call-external-antigravity.err
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
HOST="$(bash "$LIB_DIR/detect-host.sh" || echo unknown)"
log "host=$HOST  depth=$DEPTH  timeout=${TIMEOUT}s"

# 5. Route to opposite partner
case "$HOST" in
  claude)
    if claude plugin list 2>/dev/null | grep -q "codex@openai-codex"; then
      log "primary: codex via /codex:adversarial-review (official plugin detected)"
      log "         NOTE: slash invocation requires interactive Claude session;"
      log "         falling back to codex exec for unattended use"
    fi
    if call_codex; then exit 0; fi
    log "codex exec failed; trying grok"
    if call_grok; then exit 0; fi
    log "grok failed; trying pi"
    if call_pi; then exit 0; fi
    log "pi failed; trying Gemini via Antigravity"
    ;;
  codex)
    if call_claude; then exit 0; fi
    log "claude -p failed; trying grok"
    if call_grok; then exit 0; fi
    log "grok failed; trying pi"
    if call_pi; then exit 0; fi
    log "pi failed; trying Gemini via Antigravity"
    ;;
  grok)
    if call_codex; then exit 0; fi
    log "codex exec failed; trying claude"
    if call_claude; then exit 0; fi
    log "claude -p failed; trying pi"
    if call_pi; then exit 0; fi
    log "pi failed; trying Gemini via Antigravity"
    ;;
  pi)
    if call_codex; then exit 0; fi
    log "codex exec failed; trying claude"
    if call_claude; then exit 0; fi
    log "claude -p failed; trying grok"
    if call_grok; then exit 0; fi
    log "grok failed; trying Gemini via Antigravity"
    ;;
  unknown|*)
    log "host=unknown - set ADVERSARIAL_REVIEW_HOST manually; trying grok, then pi, then Gemini via Antigravity"
    if call_grok; then exit 0; fi
    log "grok failed; trying pi"
    if call_pi; then exit 0; fi
    log "pi failed; trying Gemini via Antigravity"
    ;;
esac

# 6. Gemini via Antigravity CLI (fallback for both directions)
if call_antigravity_gemini; then
  exit 0
fi
log "Antigravity Gemini fallback unavailable or failed"

# 7. Degraded mode - host-self analysis with explicit banner
log "DEGRADED MODE - no external partner available; host will self-review"
printf '⚠️  DEGRADED MODE - Cross-host principle violated\n\n'
printf 'No external partner (Codex / Claude / Grok / Pi / Antigravity) was reachable. '
printf 'The host is reviewing its own work, which the principle forbids - '
printf 'output below is single-perspective and may have blind spots.\n\n'
printf '%s\n%s\n' '-- original prompt --' "$prompt"
exit 2
