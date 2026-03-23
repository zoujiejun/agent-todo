---
name: agent-todo
description: Turn conversational promises into an automated execution queue. Use this skill when: you need to schedule background tasks, "do something later" during heartbeats, replace passive reminders with auto-executing tasks, or track multi-step goals with success criteria. Triggers: task queue, background execution, follow-up, heartbeat automation.
metadata:
  repo: https://github.com/zoujiejun/agent-todo
  author: 云舟
  version: 1.1.5
---

# agent-todo Skill

Use this skill as an execution queue, not as a passive reminder list.

核心原则：heartbeat 来时，不是提醒“有任务没做”，而是挑出下一条任务并立即执行；完成后按 source 生成可直接回写的汇报内容。

## Core commands

```bash
bash ./script.sh add "Publish release" \
  --task-type publish \
  --owner "云舟" \
  --source "forum:#19/reply:88" \
  --next-action "Push main to GitHub and publish ClawHub version" \
  --success-criteria "GitHub and ClawHub are both updated"

bash ./script.sh plan "Open-source release" \
  --task-type publish \
  --owner "云舟" \
  --source "chat:direct" \
  --steps "Update README; Push GitHub; Publish ClawHub"

bash ./script.sh run-pending --claim
bash ./script.sh done <id> --note "what was completed"
bash ./script.sh report <id>
bash ./script.sh block <id> --reason "why blocked"
```

## Workflow

1. Add tasks with enough execution context:
   - `task_type`
   - `next_action`
   - `success_criteria`
   - `source`
2. For composite goals, prefer `plan` to split them into concrete steps.
3. During heartbeat, run:
   - `bash ./script.sh run-pending --claim`
4. If it returns `EXECUTE_NOW`, do the task immediately.
5. Prefer continuing a `running` task before opening a fresh `pending` one.
6. After execution:
   - success → `done`
   - generate reply text → `report`
   - cannot continue → `block`
   - no longer needed → `cancel`

## Statuses

- `pending`: queued but not started
- `running`: currently being executed
- `blocked`: cannot continue without input or dependency
- `done`: completed
- `cancelled`: intentionally dropped

## Notes

- `agent-todo` is standalone and does not depend on `agent-forum`.
- `agent-forum` can still be used as an optional task source.
- `check-overdue` remains available for visibility, but it is no longer the main heartbeat path.
- `report` generates different output shapes for forum sources and direct chat sources.
- Use `doctor` and `setup-heartbeat` to ensure the skill is actually wired into the user's heartbeat flow.
