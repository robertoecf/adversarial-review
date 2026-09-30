#!/usr/bin/env bash
# Opção explícita somente com escolha do usuário. Não altera o roteamento default.
# ADVERSARIAL_REVIEW_REVIEWER=claude exige MODEL e EFFORT explícitos.
# Falha não troca de provider/modelo; depth, timeout e isolamento permanecem.
call_claude() {
  local model="${ADVERSARIAL_REVIEW_CLAUDE_MODEL:-opus}"
  local effort="${ADVERSARIAL_REVIEW_CLAUDE_EFFORT:-xhigh}"
  local format="${ADVERSARIAL_REVIEW_CLAUDE_OUTPUT_FORMAT:-text}"
  local input="${ADVERSARIAL_REVIEW_CLAUDE_INPUT_FORMAT:-text}"
  case "$input" in text|stream-json) ;; *) log "ERROR: invalid Claude input format"; return 1 ;; esac
  case "$effort" in low|medium|high|xhigh|max) ;; *) log "ERROR: invalid Claude effort"; return 1 ;; esac
  case "$format" in text|json|stream-json) ;; *) log "ERROR: invalid Claude output format"; return 1 ;; esac
  if [ "$input" = "stream-json" ] && [ "$format" != "stream-json" ]; then
    log "ERROR: stream-json input requires stream-json output"; return 1
  fi
  local mode_flags=(--bare)
  case "${ADVERSARIAL_REVIEW_CLAUDE_AUTH:-api}" in
    api) ;;
    subscription) mode_flags=(--setting-sources "" --settings '{"disableAllHooks":true}' --disable-slash-commands) ;;
    *) log "ERROR: invalid Claude auth mode"; return 1 ;;
  esac
  case "${ADVERSARIAL_REVIEW_CLAUDE_EXECUTION:-local}" in
    local) ;;
    cloud)
      if [ "${ADVERSARIAL_REVIEW_CLAUDE_CLOUD_REVIEW_MODE:-}" != "plan-no-connectors" ]; then
        log "ERROR: cloud review requires verified session Plan mode with connectors disabled (CLOUD_REVIEW_MODE=plan-no-connectors)"; return 1
      fi
      if [ "$input" != "text" ] || [ "$format" = "stream-json" ]; then
        log "ERROR: Claude cloud dispatch supports text input and text/json acknowledgment only"; return 1
      fi
      local cloud_session="${ADVERSARIAL_REVIEW_CLAUDE_CLOUD_SESSION:-}"
      if [[ ! "$cloud_session" =~ ^session_[a-zA-Z0-9]+$ ]]; then
        log "ERROR: cloud review requires an existing Claude cloud session ID"; return 1
      fi
      mode_flags+=(--cloud "$cloud_session" --forward-home-settings false)
      ;;
    *) log "ERROR: invalid Claude execution mode"; return 1 ;;
  esac
  if [ "$format" = "stream-json" ]; then mode_flags+=(--verbose); fi
  if ! command -v claude >/dev/null 2>&1; then return 1; fi
  if [ "${ADVERSARIAL_REVIEW_CLAUDE_EXECUTION:-local}" = "cloud" ]; then
    log "cloud session=$cloud_session: tools/permissions/model/effort are governed by the remote session, not local flags; verify $model/$effort, Plan mode and disabled connectors before dispatch. Timeout/depth guard cover local dispatch only."
  else
    log "calling: claude -p --model $model --effort $effort auth=${ADVERSARIAL_REVIEW_CLAUDE_AUTH:-api} --tools Read,Grep,Glob (DEPTH=$((DEPTH+1)))"
  fi
  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/claude-review-output.XXXXXX")" || return 1
  local review_prompt="$prompt"
  local review_id="review-${output_file##*/}"
  if [ "${ADVERSARIAL_REVIEW_CLAUDE_EXECUTION:-local}" = "cloud" ]; then
    review_prompt="Review request ID: $review_id. This is a text-only review, not an implementation-planning task: do not spawn agents, write a plan file, or call ExitPlanMode/AskUserQuestion. If higher-priority session rules require tools, report review unavailable instead of producing a verified verdict. Review only the supplied artifact, read-only and without edits. Include this exact ID in your completed verdict: $review_id.
$prompt"
    log "cloud review_id=$review_id session=$cloud_session"
  fi
  if printf '%s\n' "$review_prompt" | run_with_timeout "$TIMEOUT" env ADVERSARIAL_REVIEW_DEPTH=$((DEPTH+1)) \
    claude -p --model "$model" --effort "$effort" "${mode_flags[@]}" --tools "Read,Grep,Glob" \
    --strict-mcp-config --mcp-config '{"mcpServers":{}}' --no-session-persistence \
    --input-format "$input" --output-format "$format" >"$output_file" 2>>"$LOG_DIR/claude.err"; then
    if [ -s "$output_file" ]; then
      if [ "${ADVERSARIAL_REVIEW_CLAUDE_EXECUTION:-local}" = "cloud" ]; then
        cat "$output_file" >>"$LOG_DIR/claude-cloud-ack.log"
        rm -f "$output_file"
        log "QUEUED: review_id=$review_id session=$cloud_session; retrieve the completed response with this exact review_id. ACK is not a verdict."
        return 3
      fi
      cat "$output_file"
      rm -f "$output_file"
      return 0
    fi
  fi
  cat "$output_file" >>"$LOG_DIR/claude.err"
  rm -f "$output_file"
  return 1
}

dispatch_explicit_reviewer() {
  local reviewer="${ADVERSARIAL_REVIEW_REVIEWER:-}"
  if [ "${ADVERSARIAL_REVIEW_CLAUDE_EXECUTION:-local}" = "cloud" ] && [ "$reviewer" != "claude" ]; then
    log "ERROR: cloud execution requires explicit Claude reviewer; no automatic fallback"; exit 1
  fi
  [ -n "$reviewer" ] || return 0
  if [ "$reviewer" != "claude" ]; then
    log "ERROR: unsupported explicit reviewer: $reviewer"; exit 1
  fi
  local author
  author="$(normalize_author "${ADVERSARIAL_REVIEW_AUTHOR:-unknown}")"
  if [ "$HOST" = "claude" ] || [ "$author" = "claude" ] || [ "$author" = "unknown" ]; then
    log "ERROR: explicit Claude requires a known non-Claude author and non-Claude host"; exit 1
  fi
  if [ -z "${ADVERSARIAL_REVIEW_CLAUDE_MODEL:-}" ] || [ -z "${ADVERSARIAL_REVIEW_CLAUDE_EFFORT:-}" ]; then
    log "ERROR: explicit Claude requires model and effort"; exit 1
  fi
  local status=0
  call_claude || status=$?
  if [ "$status" = 0 ] || [ "$status" = 3 ]; then exit "$status"; fi
  log "ERROR: explicitly requested Claude failed; no silent fallback"
  exit 1
}
