#!/usr/bin/env bash
# call-external.sh - call the OPPOSITE agent for adversarial review.
#
# Cross-host principle: "the partner reviews, never the host"
#   Tiers (user decision 2026-09-28): T1 Claude and Codex review each other;
#   T2 Pi chain (opencode-go DeepSeek, GLM, then Grok); T3 Gemini (last resort).
#   host=claude -> Claude-authored work (default): T1 Astra via Pi, then codex
#                  exec. Codex-authored work: T1 is the host main loop itself, so
#                  this script only supplies T2/T3 second opinions.
#   host=codex  -> Codex/user/unknown-authored work: T1 claude -p. Claude, Pi or
#                  Grok-authored work: T1 codex exec. Then T2, then T3.
#   host=grok   -> external=codex Astra medium/high, then Gemini
#   host=pi     -> external=codex Astra medium/high, then claude, then grok (never pi itself)
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
#                                    used by host=codex author inference (always codex)
#   ADVERSARIAL_REVIEW_AUTHOR        artifact author for host=claude (default claude)
#                                    and host=codex: codex, grok, claude, pi, user, or
#                                    unknown; aliases sol, openai, astra, xai, and
#                                    anthropic are accepted
#   ADVERSARIAL_REVIEW_DEPTH         anti-recursion counter; refuse if >= 1
#   ADVERSARIAL_REVIEW_TIMEOUT       seconds; default 300
#   ADVERSARIAL_REVIEW_CODEX_EFFORT  Codex reviewer effort: medium or high; default
#                                    high on host=claude, medium elsewhere
#   ADVERSARIAL_REVIEW_FORCE_DEGRADED  if "1", skip externals and go straight to degraded
#                                      (for non-destructive smoke tests)
#   ADVERSARIAL_REVIEW_GROK_MODELS     Comma-separated direct-xAI model chain;
#                                      default grok-4.7,grok-4.6
#   ADVERSARIAL_REVIEW_GROK_MODEL      Back-compat single direct-xAI model override
#   ADVERSARIAL_REVIEW_GROK_EFFORT     Grok CLI reasoning effort; default xhigh
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
CODEX_EFFORT="${ADVERSARIAL_REVIEW_CODEX_EFFORT:-medium}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/adversarial-review"

case "$CODEX_EFFORT" in
  medium|high) ;;
  *)
    printf '[call-external] ERROR: ADVERSARIAL_REVIEW_CODEX_EFFORT must be medium or high, got: %s\n' "$CODEX_EFFORT" >&2
    exit 1
    ;;
esac

if ! mkdir -p "$LOG_DIR"; then
  printf '[call-external] ERROR: cannot create log directory: %s\n' "$LOG_DIR" >&2
  exit 1
fi
chmod 700 "$LOG_DIR" 2>/dev/null || true

# Keep operator logs on the original stderr even when call sites redirect
# run_and_emit_on_success stderr into provider *.err files.
if [ -z "${CALL_EXTERNAL_LOG_FD:-}" ]; then
  exec 3>&2
  CALL_EXTERNAL_LOG_FD=3
fi
log() { printf '[call-external] %s\n' "$*" >&"$CALL_EXTERNAL_LOG_FD"; }

normalize_author() {
  local raw="${1:-}"
  local lower
  lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    "") printf '\n' ;;
    codex|sol|openai|astra) printf 'codex\n' ;;
    grok|xai) printf 'grok\n' ;;
    claude|anthropic) printf 'claude\n' ;;
    pi|user|unknown) printf '%s\n' "$lower" ;;
    *)
      log "WARN: invalid ADVERSARIAL_REVIEW_AUTHOR=${raw}; using unknown"
      printf 'unknown\n'
      ;;
  esac
}

run_with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import math
import os
import signal
import subprocess
import sys
import time

try:
    seconds = float(sys.argv[1])
    if not math.isfinite(seconds) or seconds <= 0:
        raise ValueError()
except (ValueError, IndexError):
    print("[call-external] ERROR: timeout must be positive and finite", file=sys.stderr)
    sys.exit(125)

child = None
pending_signal = None

class Interrupted(BaseException):
    pass

def interrupted(signum, frame):
    global pending_signal
    pending_signal = signum
    if child is not None:
        raise Interrupted(signum)

def cleanup():
    # Ignore repeat shutdown signals while terminating only our owned group.
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + 1
    try:
        child.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass
    time.sleep(max(0, deadline - time.monotonic()))
    # The leader may have exited while descendants still ignore SIGTERM.
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait()

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    child = subprocess.Popen(sys.argv[2:], start_new_session=True)
    if pending_signal is not None:
        raise Interrupted(pending_signal)
    try:
        code = child.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        cleanup()
        sys.exit(124)
    sys.exit(code if code >= 0 else 128 - code)
except (KeyboardInterrupt, Interrupted) as error:
    if child is not None:
        cleanup()
    sys.exit(128 + (error.args[0] if isinstance(error, Interrupted) else signal.SIGINT))
except FileNotFoundError:
    sys.exit(127)
except PermissionError:
    sys.exit(126)
' "$secs" "$@"
  else
    log "ERROR: timeout, gtimeout and python3 unavailable; refusing unbounded execution"
    return 125
  fi
}

run_and_emit_on_success() {
  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/call-external-output.XXXXXX")" || return 1
  if "$@" >"$output_file"; then
    if [ ! -s "$output_file" ]; then
      log "WARN: external command exited 0 with empty stdout; treating as failure"
      rm -f "$output_file"
      return 1
    fi
    cat "$output_file"
    rm -f "$output_file"
    return 0
  fi
  rm -f "$output_file"
  return 1
}

call_grok() {
  local models_csv="${ADVERSARIAL_REVIEW_GROK_MODELS:-${ADVERSARIAL_REVIEW_GROK_MODEL:-grok-4.7,grok-4.6}}"
  local default_effort
  if [ "${ADVERSARIAL_REVIEW_GROK_EFFORT+x}" = "x" ]; then
    default_effort="$ADVERSARIAL_REVIEW_GROK_EFFORT"
  else
    default_effort="xhigh"
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

  local models_csv="${ADVERSARIAL_REVIEW_PI_MODELS:-${ADVERSARIAL_REVIEW_PI_MODEL:-opencode-go/deepseek-v4.1-flash:xhigh,opencode-go/glm-5.3:high,xai-oauth/grok-4.7:high}}"
  local pi_thinking
  if [ "${ADVERSARIAL_REVIEW_PI_THINKING+x}" = "x" ]; then
    pi_thinking="$ADVERSARIAL_REVIEW_PI_THINKING"
  else
    pi_thinking="xhigh"
  fi
  # Reviewer sees only the supplied prompt: skip skill listing, prompt
  # templates, and AGENTS.md/CLAUDE.md context files. Extensions stay on
  # (~100 tokens) so provider tweaks such as xAI priority tier still apply.
  local lean=(--no-skills --no-prompt-templates --no-context-files)
  # Read-only tools let the reviewer verify claims against the checkout.
  local tools=(--tools read,grep,find,ls)
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
      log "calling: pi -p --mode text --tools read,grep,find,ls --no-session (configured default override, DEPTH=$((DEPTH+1)))"
      if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
        pi -p --mode text "${tools[@]}" --no-session "${lean[@]}" "$prompt" \
        2>>"$LOG_DIR/pi.err" </dev/null; then
        return 0
      fi
      log "pi model failed: configured default override"
      continue
    fi

    case "$model" in
      *:off|*:minimal|*:low|*:medium|*:high|*:xhigh)
        log "calling: pi -p --mode text --tools read,grep,find,ls --no-session --model ${model} (DEPTH=$((DEPTH+1)))"
        if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
          pi -p --mode text "${tools[@]}" --no-session "${lean[@]}" --model "$model" "$prompt" \
          2>>"$LOG_DIR/pi.err" </dev/null; then
          return 0
        fi
        ;;
      *)
        if [ "$is_first_model" -eq 1 ] && [ -n "$pi_thinking" ]; then
          log "calling: pi -p --mode text --tools read,grep,find,ls --no-session --model ${model} --thinking ${pi_thinking} (DEPTH=$((DEPTH+1)))"
          if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
            pi -p --mode text "${tools[@]}" --no-session "${lean[@]}" --model "$model" --thinking "$pi_thinking" "$prompt" \
            2>>"$LOG_DIR/pi.err" </dev/null; then
            return 0
          fi
        else
          log "calling: pi -p --mode text --tools read,grep,find,ls --no-session --model ${model} (DEPTH=$((DEPTH+1)))"
          if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
            pi -p --mode text "${tools[@]}" --no-session "${lean[@]}" --model "$model" "$prompt" \
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
  log "calling: codex exec -m gpt-6-astra -c model_reasoning_effort=${CODEX_EFFORT} --sandbox read-only (DEPTH=$((DEPTH+1)))"
  run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
    codex exec -m gpt-6-astra -c model_reasoning_effort="$CODEX_EFFORT" --sandbox read-only --skip-git-repo-check "$prompt" \
    2>>"$LOG_DIR/codex.err" </dev/null
}

source "$LIB_DIR/claude-reviewer.sh"

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

  local models_csv="${ADVERSARIAL_REVIEW_ANTIGRAVITY_MODELS:-gemini-3.8-flash-high,gemini-3.7-flash-high,gemini-3.1-pro-high}"
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

    if [ "$catalog_available" -eq 1 ] && ! printf '%s\n' "$catalog" \
      | awk -v wanted="$model" '$1 == wanted { found = 1 } END { exit !found }'; then
      log "Antigravity model unavailable, skipping: ${model}"
      continue
    fi

    log "calling: ${cmd} -p <prompt> --model ${model} --sandbox --mode plan (DEPTH=$((DEPTH+1)))"
    if run_and_emit_on_success run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
      "$cmd" -p "$prompt" --print-timeout "${TIMEOUT}s" --model "$model" --sandbox --mode plan \
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
dispatch_explicit_reviewer

# 5. Route to opposite partner
case "$HOST" in
  claude)
    AUTHOR="$(normalize_author "${ADVERSARIAL_REVIEW_AUTHOR:-claude}")"
    CODEX_EFFORT="${ADVERSARIAL_REVIEW_CODEX_EFFORT:-high}"
    T2_MODELS="${ADVERSARIAL_REVIEW_PI_MODELS:-}"
    if [ "$AUTHOR" = "grok" ] && [ -z "$T2_MODELS" ]; then
      T2_MODELS="opencode-go/deepseek-v4.1-flash:xhigh,opencode-go/glm-5.3:high"
    fi
    if [ "$AUTHOR" = "codex" ]; then
      log "author=codex - T1 is the host main loop; supplying T2, never codex"
    else
      log "author=${AUTHOR} - T1 Astra via pi, then codex exec"
      if ADVERSARIAL_REVIEW_PI_MODELS="openai-codex/gpt-6-astra:${CODEX_EFFORT}" call_pi; then exit 0; fi
      log "pi Astra failed; trying codex exec"
      if call_codex; then exit 0; fi
      log "codex exec failed; trying T2 pi chain"
    fi
    if ADVERSARIAL_REVIEW_PI_MODELS="$T2_MODELS" call_pi; then exit 0; fi
    log "T2 pi chain failed; trying T3 Antigravity model ladder"
    ;;
  codex)
    ARTIFACT="${ADVERSARIAL_REVIEW_ARTIFACT:-code}"
    AUTHOR="$(normalize_author "${ADVERSARIAL_REVIEW_AUTHOR:-}")"
    if [ -z "$AUTHOR" ]; then
      # The default Codex interactive model is Astra, so omitted authors are Codex-owned.
      AUTHOR=codex
      log "artifact=${ARTIFACT} author omitted; inferred author=codex"
    else
      log "artifact=${ARTIFACT} author=${AUTHOR}"
    fi

    case "$AUTHOR" in
      codex|user|unknown)
        if ADVERSARIAL_REVIEW_CLAUDE_AUTH="${ADVERSARIAL_REVIEW_CLAUDE_AUTH:-subscription}" call_claude; then exit 0; fi
        log "T1 claude -p failed; trying T2 pi chain"
        if call_pi; then exit 0; fi
        ;;
      claude|pi)
        if call_codex; then exit 0; fi
        log "T1 codex exec failed; trying T2 pi chain"
        if call_pi; then exit 0; fi
        ;;
      grok)
        if call_codex; then exit 0; fi
        log "T1 codex exec failed; trying T2 non-xAI pi chain"
        if ADVERSARIAL_REVIEW_PI_MODELS="opencode-go/deepseek-v4.1-flash:xhigh,opencode-go/glm-5.3:high" call_pi; then exit 0; fi
        ;;
    esac
    log "T2 failed; trying T3 Antigravity Gemini ladder"
    ;;
  grok)
    if call_codex; then exit 0; fi
    log "codex exec failed; trying Antigravity Gemini ladder"
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

# 6. Gemini Antigravity CLI ladder
if call_antigravity; then
  exit 0
fi
log "Antigravity model ladder unavailable or failed"

# 7. Degraded mode - host-self analysis with explicit banner
log "DEGRADED MODE - no external partner available; host will self-review"
log "Before accepting DEGRADED, spawn a same-family subagent with clean context and read-only tools; label it EXTERNAL_SAME_FAMILY"
printf '⚠️  DEGRADED MODE - Cross-host principle violated\n\n'
printf 'No external partner (Codex / Claude / Grok / Pi / Antigravity) was reachable. '
printf 'The host is reviewing its own work, which the principle forbids - '
printf 'output below is single-perspective and may have blind spots.\n\n'
printf '%s\n%s\n' '-- original prompt --' "$prompt"
exit 2
