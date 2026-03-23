#!/usr/bin/env bash
# todo.sh - execution queue for agent-todo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=todo_lib.sh
source "${SCRIPT_DIR}/todo_lib.sh"

COMMAND="${1:-}"
shift 2>/dev/null || true

usage() {
  cat <<'EOF'
agent-todo - agent execution queue

Usage:
  todo.sh init
  todo.sh doctor
  todo.sh setup-heartbeat [--write]
  todo.sh add <title> [options]
  todo.sh plan <title> --steps "step1; step2; step3" [options]
  todo.sh list [options]
  todo.sh show <id>
  todo.sh report <id>
  todo.sh run-pending [options]
  todo.sh start <id>
  todo.sh block <id> --reason "..."
  todo.sh unblock <id>
  todo.sh done <id> --note "..."
  todo.sh cancel <id> --reason "..."
  todo.sh check-overdue

Add/plan options:
  --task-type <type>            Task type (general|coding|doc|research|reply|review|publish)
  --deadline <time>             Deadline (ISO-8601 or natural language)
  --owner <name>                Task owner
  --requester <name>            Requester
  --source <source>             Source (forum:#19, chat:direct, ...)
  --next-action <text>          Next concrete action to take
  --success-criteria <text>     What counts as done
  --tags <tags>                 Comma-separated tags
  --parent-id <id>              Parent task ID (for child tasks)
  --depends-on <ids>            Comma-separated task IDs this depends on
  --steps <text>                Semicolon-separated steps for plan (creates parent + ordered children)

List options:
  --owner <name>
  --status <status>             pending|running|blocked|done|cancelled

Run-pending options:
  --owner <name>
  --claim                       Move selected task to running before printing execution brief
  (blocked tasks are excluded; use 'unblock <id>' to restore a blocked task)
EOF
}

workspace_root() {
  dirname "$TODO_DB"
}

heartbeat_file() {
  echo "$(workspace_root)/HEARTBEAT.md"
}

heartbeat_command() {
  echo "${SCRIPT_DIR}/script.sh run-pending --claim"
}

heartbeat_configured() {
  local hb_file
  hb_file="$(heartbeat_file)"
  [[ -f "$hb_file" ]] && grep -Fq "$(heartbeat_command)" "$hb_file"
}

print_heartbeat_hint() {
  if heartbeat_configured; then
    return
  fi

  local hb_file cmd
  hb_file="$(heartbeat_file)"
  cmd="$(heartbeat_command)"
  echo
  echo "⚠️ agent-todo is not wired into heartbeat yet."
  echo "Add this to: ${hb_file}"
  echo "$cmd"
  echo "Or run: ./script.sh setup-heartbeat --write"
}

parse_deadline() {
  local deadline="$1"
  [[ -z "$deadline" ]] && echo "" && return
  date -d "$deadline" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo "$deadline"
}

row_field() {
  local row="$1"
  local index="$2"
  IFS='|' read -r -a f <<< "$row"
  echo "${f[$index]:-}" | xargs
}

load_task() {
  local id="$1"
  TASK_ID="$id"
  TASK_TITLE="$(get_field "$id" title)"
  TASK_TYPE="$(get_field "$id" task_type)"
  TASK_OWNER="$(get_field "$id" owner)"
  TASK_REQUESTER="$(get_field "$id" requester)"
  TASK_SOURCE="$(get_field "$id" source)"
  TASK_STATUS="$(get_field "$id" status)"
  TASK_DEADLINE="$(get_field "$id" deadline)"
  TASK_NEXT_ACTION="$(get_field "$id" next_action)"
  TASK_SUCCESS_CRITERIA="$(get_field "$id" success_criteria)"
  TASK_CREATED_AT="$(get_field "$id" created_at)"
  TASK_UPDATED_AT="$(get_field "$id" updated_at)"
  TASK_LAST_ATTEMPT_AT="$(get_field "$id" last_attempt_at)"
  TASK_COMPLETED_AT="$(get_field "$id" completed_at)"
  TASK_RESULT="$(get_field "$id" result)"
  TASK_TAGS="$(get_field "$id" tags)"
  TASK_PARENT_ID="$(get_field "$id" parent_id)"
  TASK_DEPENDS_ON="$(get_field "$id" depends_on)"

  if [[ -z "$TASK_TITLE" ]]; then
    echo "未找到任务: $id" >&2
    exit 1
  fi
}

save_task() {
  local new_row
  new_row=$(build_row \
    "$TASK_ID" "$TASK_TITLE" "$TASK_TYPE" "$TASK_OWNER" "$TASK_REQUESTER" "$TASK_SOURCE" \
    "$TASK_STATUS" "$TASK_DEADLINE" "$TASK_NEXT_ACTION" "$TASK_SUCCESS_CRITERIA" \
    "$TASK_CREATED_AT" "$TASK_UPDATED_AT" "$TASK_LAST_ATTEMPT_AT" "$TASK_COMPLETED_AT" \
    "$TASK_RESULT" "$TASK_TAGS" "$TASK_PARENT_ID" "$TASK_DEPENDS_ON")
  replace_row "$TASK_ID" "$new_row"
}

render_report() {
  local title="$1"
  local source="$2"
  local completed_at="$3"
  local result="$4"
  local success_criteria="$5"

  if [[ "$source" =~ ^forum:#([0-9]+)(/reply:([0-9]+))?$ ]]; then
    local topic_id="${BASH_REMATCH[1]}"
    printf '【回帖内容】\n'
    printf '✅ 已完成：%s\n' "$title"
    printf ' - 话题：#%s\n' "$topic_id"
    printf ' - 完成时间：%s\n' "$completed_at"
    [[ -n "$result" ]] && printf ' - 结果：%s\n' "$result"
    [[ -n "$success_criteria" ]] && printf ' - 对照标准：%s\n' "$success_criteria"
    printf '\n如无遗漏，我这边先收口。\n'
    return
  fi

  if [[ "$source" =~ ^chat: ]]; then
    printf '【回消息内容】\n'
    printf '✅ 已完成：%s\n' "$title"
    printf ' - 完成时间：%s\n' "$completed_at"
    [[ -n "$result" ]] && printf ' - 结果：%s\n' "$result"
    [[ -n "$success_criteria" ]] && printf ' - 对照标准：%s\n' "$success_criteria"
    return
  fi

  printf '【通用汇报】\n'
  printf '✅ %s\n' "$title"
  [[ -n "$source" ]] && printf ' - source: %s\n' "$source"
  printf ' - completed_at: %s\n' "$completed_at"
  [[ -n "$result" ]] && printf ' - result: %s\n' "$result"
  [[ -n "$success_criteria" ]] && printf ' - success_criteria: %s\n' "$success_criteria"
}

queue_task() {
  local title="$1"
  local task_type="$2"
  local deadline="$3"
  local owner="$4"
  local requester="$5"
  local source="$6"
  local next_action="$7"
  local success_criteria="$8"
  local tags="${9:-}"
  local parent_id="${10:-}"
  local depends_on="${11:-}"

  local id ts parsed_deadline row
  id=$(generate_uuid)
  ts=$(now_iso)
  parsed_deadline=$(parse_deadline "$deadline")
  [[ -z "$next_action" ]] && next_action="$title"

  row=$(build_row \
    "$id" "$title" "$task_type" "$owner" "$requester" "$source" \
    "pending" "$parsed_deadline" "$next_action" "$success_criteria" \
    "$ts" "$ts" "" "" "" "$tags" "$parent_id" "$depends_on")

  echo "$row" >> "$TODO_DB"
  touch_db
  echo "$id"
}

cmd_init() {
  init_db
  echo "✅ agent-todo queue initialized: $TODO_DB"
  print_heartbeat_hint
}

cmd_doctor() {
  init_db
  local hb_file cmd
  hb_file="$(heartbeat_file)"
  cmd="$(heartbeat_command)"

  echo "agent-todo doctor"
  echo "- TODO_DB: $TODO_DB"
  echo "- HEARTBEAT.md: $hb_file"
  echo "- expected heartbeat command: $cmd"

  if heartbeat_configured; then
    echo "- heartbeat: configured ✅"
  else
    echo "- heartbeat: missing ⚠️"
    echo
    echo "Suggested block:"
    echo "## Agent execution queue"
    echo "$cmd"
  fi
}

cmd_setup_heartbeat() {
  local write_mode=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --write) write_mode=1; shift ;;
      *) echo "未知选项: $1" >&2; exit 1 ;;
    esac
  done

  init_db

  local hb_file cmd
  hb_file="$(heartbeat_file)"
  cmd="$(heartbeat_command)"

  if heartbeat_configured; then
    echo "✅ heartbeat already configured: $hb_file"
    return
  fi

  if [[ $write_mode -eq 0 ]]; then
    echo "Heartbeat not configured yet."
    echo "Add this to $hb_file:"
    echo "## Agent execution queue"
    echo "$cmd"
    echo
    echo "Or run: ./script.sh setup-heartbeat --write"
    return
  fi

  touch "$hb_file"
  {
    [[ -s "$hb_file" ]] && echo
    echo "## Agent execution queue"
    echo "$cmd"
  } >> "$hb_file"

  echo "✅ heartbeat updated: $hb_file"
  echo "   added: $cmd"
}

cmd_add() {
  local title=""
  local task_type="general"
  local deadline=""
  local owner=""
  local requester=""
  local source=""
  local next_action=""
  local success_criteria="Mark done and report back to source"
  local tags=""
  local parent_id=""
  local depends_on=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-type) task_type="$2"; shift 2 ;;
      --deadline) deadline="$2"; shift 2 ;;
      --owner) owner="$2"; shift 2 ;;
      --requester) requester="$2"; shift 2 ;;
      --source) source="$2"; shift 2 ;;
      --next-action) next_action="$2"; shift 2 ;;
      --success-criteria) success_criteria="$2"; shift 2 ;;
      --tags) tags="$2"; shift 2 ;;
      --parent-id) parent_id="$2"; shift 2 ;;
      --depends-on) depends_on="$2"; shift 2 ;;
      -*) echo "未知选项: $1" >&2; exit 1 ;;
      *) title="$1"; shift ;;
    esac
  done

  [[ -z "$title" ]] && echo "错误: 必须提供任务标题" >&2 && exit 1

  init_db
  local id
  id=$(queue_task "$title" "$task_type" "$deadline" "$owner" "$requester" "$source" "$next_action" "$success_criteria" "$tags" "$parent_id" "$depends_on")

  echo "✅ task queued [$id]"
  echo "   title: $title"
  echo "   type: $task_type"
  [[ -n "$owner" ]] && echo "   owner: $owner"
  [[ -n "$deadline" ]] && echo "   deadline: $(parse_deadline "$deadline")"
  [[ -n "$next_action" ]] && echo "   next_action: $next_action"
  [[ -n "$parent_id" ]] && echo "   parent_id: $parent_id"
  [[ -n "$depends_on" ]] && echo "   depends_on: $depends_on"
  print_heartbeat_hint
}

cmd_plan() {
  local title=""
  local task_type="general"
  local deadline=""
  local owner=""
  local requester=""
  local source=""
  local success_criteria="All planned steps are completed and reported back"
  local tags=""
  local steps=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-type) task_type="$2"; shift 2 ;;
      --deadline) deadline="$2"; shift 2 ;;
      --owner) owner="$2"; shift 2 ;;
      --requester) requester="$2"; shift 2 ;;
      --source) source="$2"; shift 2 ;;
      --success-criteria) success_criteria="$2"; shift 2 ;;
      --tags) tags="$2"; shift 2 ;;
      --steps) steps="$2"; shift 2 ;;
      -*) echo "未知选项: $1" >&2; exit 1 ;;
      *) title="$1"; shift ;;
    esac
  done

  [[ -z "$title" ]] && echo "错误: 必须提供计划标题" >&2 && exit 1
  [[ -z "$steps" ]] && echo "错误: plan 必须提供 --steps" >&2 && exit 1

  init_db

  # Step 1: Create the parent task
  local parent_id ts
  ts=$(now_iso)
  parent_id=$(queue_task "$title" "$task_type" "$deadline" "$owner" "$requester" "$source" \
    "分解步骤并推进: $title" "$success_criteria" "$tags" "" "")

  echo "📋 parent plan [$parent_id]"
  echo "   title: $title"

  # Step 2: Create child tasks with dependency chain
  local index=0 created=0 step trimmed step_title step_next step_success id prev_id
  IFS=';' read -r -a step_array <<< "$steps"
  for step in "${step_array[@]}"; do
    trimmed=$(echo "$step" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$trimmed" ]] && continue
    index=$((index + 1))
    created=$((created + 1))

    if [[ $index -eq 1 ]]; then
      # First step: no dependency
      depends_on_arg=""
    else
      # Subsequent steps: depend on previous step
      depends_on_arg="$prev_id"
    fi

    step_title="${title} / step ${index}: ${trimmed}"
    step_next="$trimmed"
    step_success="Step ${index}/${created} completed for plan: ${title}"
    id=$(queue_task "$step_title" "$task_type" "$deadline" "$owner" "$requester" "$source" \
      "$step_next" "$step_success" "$tags" "$parent_id" "$depends_on_arg")
    prev_id="$id"

    echo "✅ child $index [$id]"
    echo "   title: $step_title"
    [[ -n "$depends_on_arg" ]] && echo "   depends_on: ${depends_on_arg:0:8}..."
  done

  [[ $created -eq 0 ]] && echo "错误: --steps 里没有可用步骤" >&2 && exit 1
  echo "📦 plan queued: $title"
  echo "   parent: $parent_id"
  echo "   steps: $created"
  [[ -n "$success_criteria" ]] && echo "   success_criteria: $success_criteria"
  print_heartbeat_hint
}

cmd_list() {
  local owner_filter=""
  local status_filter=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner) owner_filter="$2"; shift 2 ;;
      --status) status_filter="$2"; shift 2 ;;
      -*) echo "未知选项: $1" >&2; exit 1 ;;
      *) shift ;;
    esac
  done

  init_db

  echo
  echo '═══════════════════════════════════════'
  echo '  agent-todo execution queue'
  echo '═══════════════════════════════════════'
  echo

  local found=0
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    local id title task_type owner source status deadline next_action
    id=$(row_field "$row" 1)
    title=$(row_field "$row" 2)
    task_type=$(row_field "$row" 3)
    owner=$(row_field "$row" 4)
    source=$(row_field "$row" 6)
    status=$(row_field "$row" 7)
    deadline=$(row_field "$row" 8)
    next_action=$(row_field "$row" 9)

    [[ -n "$owner_filter" && "$owner" != "$owner_filter" ]] && continue
    [[ -n "$status_filter" && "$status" != "$status_filter" ]] && continue

    found=1
    echo "  $(format_status "$status") [${id:0:8}]"
    echo "     title: $title"
    [[ -n "$task_type" ]] && echo "     type: $task_type"
    [[ -n "$owner" ]] && echo "     owner: $owner"
    [[ -n "$deadline" ]] && echo "     deadline: $deadline"
    [[ -n "$source" ]] && echo "     source: $source"
    [[ -n "$next_action" ]] && echo "     next_action: $next_action"
    echo
  done < <(find_rows)

  [[ $found -eq 0 ]] && echo '  (no matching tasks)' && echo
}

cmd_show() {
  local id="$1"
  [[ -z "$id" ]] && echo "错误: 必须提供任务ID" >&2 && exit 1
  init_db
  load_task "$id"

  echo
  echo '═══════════════════════════════════════'
  echo '  task detail'
  echo '═══════════════════════════════════════'
  echo "  id:               $TASK_ID"
  echo "  title:            $TASK_TITLE"
  echo "  task_type:        $TASK_TYPE"
  echo "  owner:            $TASK_OWNER"
  echo "  requester:        $TASK_REQUESTER"
  echo "  source:           $TASK_SOURCE"
  echo "  status:           $TASK_STATUS"
  echo "  deadline:         $TASK_DEADLINE"
  echo "  next_action:      $TASK_NEXT_ACTION"
  echo "  success_criteria: $TASK_SUCCESS_CRITERIA"
  echo "  created_at:       $TASK_CREATED_AT"
  echo "  updated_at:       $TASK_UPDATED_AT"
  echo "  last_attempt_at:  $TASK_LAST_ATTEMPT_AT"
  echo "  completed_at:     $TASK_COMPLETED_AT"
  echo "  result:           $TASK_RESULT"
  echo "  tags:             $TASK_TAGS"
  echo "  parent_id:        $TASK_PARENT_ID"
  echo "  depends_on:       $TASK_DEPENDS_ON"
  echo
}

cmd_report() {
  local id="$1"
  [[ -z "$id" ]] && echo "错误: 必须提供任务ID" >&2 && exit 1
  init_db
  load_task "$id"
  render_report "$TASK_TITLE" "$TASK_SOURCE" "$TASK_COMPLETED_AT" "$TASK_RESULT" "$TASK_SUCCESS_CRITERIA"
}

cmd_start() {
  local id="$1"
  [[ -z "$id" ]] && echo "错误: 必须提供任务ID" >&2 && exit 1
  init_db
  load_task "$id"

  local ts
  ts=$(now_iso)
  TASK_STATUS="running"
  TASK_LAST_ATTEMPT_AT="$ts"
  TASK_UPDATED_AT="$ts"
  save_task

  echo "🏃 task started [$TASK_ID]"
  echo "   title: $TASK_TITLE"
}

cmd_block() {
  local id="$1"
  local reason=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -z "$id" ]] && echo "错误: 必须提供任务ID" >&2 && exit 1
  init_db
  load_task "$id"

  local ts
  ts=$(now_iso)
  TASK_STATUS="blocked"
  TASK_UPDATED_AT="$ts"
  TASK_RESULT="$reason"
  save_task

  echo "🧱 task blocked [$TASK_ID]"
  [[ -n "$reason" ]] && echo "   reason: $reason"
}

cmd_unblock() {
  local id="$1"
  [[ -z "$id" ]] && echo "错误: 必须提供任务ID" >&2 && exit 1
  init_db
  load_task "$id"

  if [[ "$TASK_STATUS" != "blocked" ]]; then
    echo "⚠️ 任务 [$TASK_ID] 状态是 $TASK_STATUS，不是 blocked，无需 unblock"
    return
  fi

  local ts
  ts=$(now_iso)
  TASK_STATUS="pending"
  TASK_UPDATED_AT="$ts"
  # 保留原有的 block reason，但清空以示已解除
  save_task

  echo "✅ task unblocked [$TASK_ID]"
  echo "   title: $TASK_TITLE"
  echo "   status: pending (ready to be picked up by run-pending)"
}

reply_to_source() {
  local source="$1"
  local report_text="$2"

  # forum source: POST reply via agent-forum API
  if [[ "$source" =~ ^forum:#([0-9]+)(/reply:([0-9]+))?$ ]]; then
    local topic_id="${BASH_REMATCH[1]}"
    local forum_url="${FORUM_URL:-http://localhost:8080}"
    local forum_agent_name="${FORUM_AGENT_NAME:-${AGENT_NAME:-}}"

    if [[ -z "$forum_agent_name" ]]; then
      echo "[auto-reply] ⚠️ FORUM_AGENT_NAME not set, skipping forum post" >&2
      echo "$report_text"
      return
    fi

    # Escape double quotes and newlines for JSON
    local escaped_content
    escaped_content=$(printf '%s' "$report_text" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null) \
      || escaped_content=$(printf '%s' "$report_text" | jq -Rs '.' 2>/dev/null) \
      || { echo "[auto-reply] ⚠️ cannot JSON-escape content, skipping forum post" >&2; echo "$report_text"; return; }

    local payload="{\"content\":$escaped_content}"
    local reply_url="${forum_url}/api/topics/${topic_id}/replies"

    local http_code
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" \
      -X POST "$reply_url" \
      -H "Content-Type: application/json" \
      -H "X-Agent-Name: ${forum_agent_name}" \
      -d "$payload" 2>/dev/null || echo "000")

    if [[ "$http_code" =~ ^[2] ]]; then
      echo "[auto-reply] ✅ forum:#${topic_id} 汇报已自动回写"
    else
      echo "[auto-reply] ⚠️ forum回写失败 (HTTP $http_code)，以下为汇报内容：" >&2
      echo "$report_text"
    fi
    return
  fi

  # chat:direct source: print report with auto-reply marker
  if [[ "$source" == "chat:direct" ]]; then
    echo
    echo "[AUTO_REPLY:chat:direct]"
    echo "$report_text"
    return
  fi

  # other sources: just print the report
  echo "$report_text"
}

cmd_done() {
  local id="$1"
  local note=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --note) note="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -z "$id" ]] && echo "错误: 必须提供任务ID" >&2 && exit 1
  init_db
  load_task "$id"

  local ts
  ts=$(now_iso)
  TASK_STATUS="done"
  TASK_UPDATED_AT="$ts"
  TASK_COMPLETED_AT="$ts"
  TASK_RESULT="$note"
  save_task

  echo "✅ task done [$TASK_ID]"
  echo "   title: $TASK_TITLE"
  echo
  echo '═══ completion report ═══'
  local report_text
  report_text=$(render_report "$TASK_TITLE" "$TASK_SOURCE" "$TASK_COMPLETED_AT" "$TASK_RESULT" "$TASK_SUCCESS_CRITERIA")
  reply_to_source "$TASK_SOURCE" "$report_text"
}

cmd_cancel() {
  local id="$1"
  local reason=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -z "$id" ]] && echo "错误: 必须提供任务ID" >&2 && exit 1
  init_db
  load_task "$id"

  local ts
  ts=$(now_iso)
  TASK_STATUS="cancelled"
  TASK_UPDATED_AT="$ts"
  TASK_RESULT="$reason"
  save_task

  echo "❌ task cancelled [$TASK_ID]"
  [[ -n "$reason" ]] && echo "   reason: $reason"
}

cmd_check_overdue() {
  init_db
  local found=0
  echo
  echo '═══ overdue tasks ═══'
  echo
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    local id title status deadline
    id=$(row_field "$row" 1)
    title=$(row_field "$row" 2)
    status=$(row_field "$row" 7)
    deadline=$(row_field "$row" 8)
    [[ "$status" =~ ^(done|cancelled)$ ]] && continue
    [[ -z "$deadline" ]] && continue
    if [[ $(deadline_to_timestamp "$deadline") -gt 0 ]] && [[ $(date '+%s') -gt $(deadline_to_timestamp "$deadline") ]]; then
      found=1
      echo "🚨 $title [$id]"
      echo "   deadline: $deadline"
    fi
  done < <(find_rows)

  [[ $found -eq 0 ]] && echo '✅ no overdue tasks'
}

cmd_run_pending() {
  local owner_filter=""
  local claim=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner) owner_filter="$2"; shift 2 ;;
      --claim) claim=1; shift ;;
      -*) echo "未知选项: $1" >&2; exit 1 ;;
      *) shift ;;
    esac
  done

  init_db

  # run-pending selection logic:
  # 1. Prefer child tasks (has parent_id) over parent/standalone tasks
  # 2. Among same preference level: running > pending, then by deadline/order
  # 3. Only pick tasks whose depends_on are all done
  #
  # Uses column-index lookup to handle empty cells in the markdown table correctly.

  local -a candidate_lines=()
  mapfile -t candidate_lines < <(awk -F'|' -v owner_filter="$owner_filter" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    NR == 7 {
      # Header row: discover column indices (handles empty cells)
      for (i = 1; i <= NF; i++) {
        $i = trim($i)
        if ($i == "id")          col_id = i
        if ($i == "owner")       col_owner = i
        if ($i == "status")      col_status = i
        if ($i == "deadline")    col_deadline = i
        if ($i == "created_at")  col_created = i
        if ($i == "last_attempt_at") col_last = i
        if ($i == "parent_id")  col_parent = i
        if ($i == "depends_on") col_deps = i
      }
      next
    }
    NR <= 6 { next }
    !/^\|/ || /^\|[-| ]+\|/ { next }
    {
      raw = $0
      for (i = 1; i <= NF; i++) $i = trim($i)
      id = (col_id      != "" ? $col_id      : "")
      owner = (col_owner != "" ? $col_owner   : "")
      status = (col_status != "" ? $col_status : "")
      deadline = (col_deadline != "" ? $col_deadline : "")
      created_at = (col_created != "" ? $col_created : "")
      last_attempt_at = (col_last != "" ? $col_last : "")
      parent_id = (col_parent != "" ? $col_parent : "")
      depends_on = (col_deps != "" ? $col_deps : "")

      if (id == "" || status == "done" || status == "cancelled" || status == "blocked") next
      if (owner_filter != "" && owner != owner_filter) next

      # Parent/standalone tasks get lower priority than child tasks
      if (parent_id == "") {
        pref = 2
      } else {
        pref = 1
      }

      if (status == "running") {
        priority = pref * 10 + 0
        order_key = (last_attempt_at != "" ? last_attempt_at : created_at)
      } else {
        priority = pref * 10 + 1
        order_key = (deadline != "" ? deadline : "9999-99-99T99:99:99+00:00")
      }

      print priority "\t" order_key "\t" created_at "\t" raw
    }
  ' "$TODO_DB" | sort -t$'\t' -k1,1n -k2,2 -k3,3 | cut -f4-)

  if [[ ${#candidate_lines[@]} -eq 0 ]]; then
    echo "HEARTBEAT_OK"
    return
  fi

  local selected_line=""
  local id=""
  local candidate_line=""
  for candidate_line in "${candidate_lines[@]}"; do
    id=$(row_field "$candidate_line" 1)
    load_task "$id"

    local all_done=1
    if [[ -n "$TASK_DEPENDS_ON" ]]; then
      IFS=',' read -r -a dep_array <<< "$TASK_DEPENDS_ON"
      for dep_id in "${dep_array[@]}"; do
        dep_id=$(echo "$dep_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$dep_id" ]] && continue
        local dep_status
        dep_status=$(get_field "$dep_id" status)
        if [[ "$dep_status" != "done" ]]; then
          all_done=0
          break
        fi
      done
    fi

    if [[ $all_done -eq 1 ]]; then
      selected_line="$candidate_line"
      break
    fi
  done

  if [[ -z "$selected_line" ]]; then
    echo "HEARTBEAT_OK"
    return
  fi

  if [[ $claim -eq 1 ]]; then
    local ts
    ts=$(now_iso)
    TASK_STATUS="running"
    TASK_LAST_ATTEMPT_AT="$ts"
    TASK_UPDATED_AT="$ts"
    save_task
  fi

  echo 'EXECUTE_NOW'
  echo "id: $TASK_ID"
  echo "title: $TASK_TITLE"
  echo "task_type: $TASK_TYPE"
  [[ -n "$TASK_OWNER" ]] && echo "owner: $TASK_OWNER"
  [[ -n "$TASK_REQUESTER" ]] && echo "requester: $TASK_REQUESTER"
  [[ -n "$TASK_SOURCE" ]] && echo "source: $TASK_SOURCE"
  [[ -n "$TASK_DEADLINE" ]] && echo "deadline: $TASK_DEADLINE"
  [[ -n "$TASK_NEXT_ACTION" ]] && echo "next_action: $TASK_NEXT_ACTION"
  [[ -n "$TASK_SUCCESS_CRITERIA" ]] && echo "success_criteria: $TASK_SUCCESS_CRITERIA"
  [[ -n "$TASK_TAGS" ]] && echo "tags: $TASK_TAGS"
  [[ -n "$TASK_PARENT_ID" ]] && echo "parent_id: $TASK_PARENT_ID"
  [[ -n "$TASK_DEPENDS_ON" ]] && echo "depends_on: $TASK_DEPENDS_ON"
  echo
  echo 'Do the task now. When finished, call:'
  echo "./script.sh done $TASK_ID --note \"what was completed\""
  echo 'If blocked, call:'
  echo "./script.sh block $TASK_ID --reason \"why it is blocked\""
  echo 'If work started but is not complete yet, keep it running and update last attempt by re-claiming on next heartbeat.'
}

case "$COMMAND" in
  init) cmd_init ;;
  doctor) cmd_doctor ;;
  setup-heartbeat) cmd_setup_heartbeat "$@" ;;
  add) cmd_add "$@" ;;
  plan) cmd_plan "$@" ;;
  list|ls) cmd_list "$@" ;;
  show|view) cmd_show "$@" ;;
  report) cmd_report "$@" ;;
  run-pending) cmd_run_pending "$@" ;;
  start) cmd_start "$@" ;;
  block) cmd_block "$@" ;;
  unblock) cmd_unblock "$@" ;;
  done|complete) cmd_done "$@" ;;
  cancel) cmd_cancel "$@" ;;
  check-overdue) cmd_check_overdue ;;
  help|--help|-h) usage ;;
  *) usage ;;
esac
