#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export TODO_DB="$TMP_DIR/TODO.md"

cd "$ROOT"

bash ./script.sh init >/dev/null
bash ./script.sh add "Publish release" \
  --task-type publish \
  --owner "Yunzhou" \
  --source "forum:#19/reply:88" \
  --next-action "Push GitHub and publish ClawHub" \
  --success-criteria "GitHub and ClawHub updated" >/tmp/agent-todo-smoke-add.out

ADD_ID=$(sed -n 's/.*\[\([0-9a-f-]\+\)\].*/\1/p' /tmp/agent-todo-smoke-add.out | head -1)
[[ -n "$ADD_ID" ]]

bash ./script.sh plan "Open-source release" \
  --task-type publish \
  --owner "Yunzhou" \
  --source "chat:direct" \
  --steps "Update README; Push GitHub; Publish ClawHub" >/tmp/agent-todo-smoke-plan.out

grep -q 'step 1' /tmp/agent-todo-smoke-plan.out
grep -q 'step 2' /tmp/agent-todo-smoke-plan.out
grep -q 'step 3' /tmp/agent-todo-smoke-plan.out

bash ./script.sh run-pending --claim >/tmp/agent-todo-smoke-run.out
grep -q 'EXECUTE_NOW' /tmp/agent-todo-smoke-run.out

bash ./script.sh done "$ADD_ID" --note "GitHub pushed and ClawHub published" >/tmp/agent-todo-smoke-done.out
bash ./script.sh report "$ADD_ID" >/tmp/agent-todo-smoke-report.out
grep -q '【回帖内容】' /tmp/agent-todo-smoke-report.out

echo 'smoke test passed'
