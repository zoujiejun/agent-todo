# agent-todo

> **Stop letting your AI agents make empty promises.**
> Chat interfaces are great for talking, but bad for doing. When an agent says "I will do this later," it usually forgets as soon as the context window clears.
>
> `agent-todo` is an active execution queue designed natively for AI agents. Instead of just adding items to a passive list, it wires directly into the agent's heartbeat—forcing the agent to automatically claim the next task, execute it in the background, and report back to the original source when finished.
>
> No more reminders. Just execution.

- GitHub: https://github.com/zoujiejun/agent-todo
- ClawHub: https://clawhub.com/skills/agent-todo
- 中文说明: [README.zh-CN.md](./README.zh-CN.md)

## What changed

This skill is now positioned as an **execution queue**, not just a reminder tool.

- heartbeat should **pick work and execute it**, not merely remind
- tasks carry **next_action** and **success_criteria**
- queue state supports **pending / running / blocked / done / cancelled**
- `run-pending` emits the next task brief for the agent to act on immediately

## Features

- **Queue tasks** with title, type, owner, deadline, next action, and success criteria
- **Claim work on heartbeat** via `run-pending --claim`
- **Track execution state** with `pending`, `running`, `blocked`, `done`, and `cancelled`
- **Generate source-aware completion reports** for forum replies and direct chats
- **Keep source context** so finished work can be reported back to the original chat or topic
- **Structure reply commitments automatically** into executable tasks with task type, next action, and success criteria
- **Prefer continuing running work** before picking a fresh pending task
- **Detect heartbeat onboarding gaps** with `doctor` and `setup-heartbeat`

## Relationship with agent-forum

`agent-todo` is a **standalone skill**. It does **not** depend on `agent-forum`.

- Use it as an agent execution queue from plain CLI
- Or wire it into OpenClaw heartbeat / reply hooks
- If you already use `agent-forum`, forum replies can be one task source, but that integration is optional

## Quick Start

### Install

```bash
git clone https://github.com/zoujiejun/agent-todo.git
cd agent-todo
chmod +x todo.sh todo_lib.sh script.sh hooks/*.sh
```

### Initialize

```bash
bash ./script.sh init
```

On first use, `agent-todo` will remind you if heartbeat has not been configured yet.

### Wire heartbeat

Check current status:

```bash
bash ./script.sh doctor
```

Show the heartbeat block to add manually:

```bash
bash ./script.sh setup-heartbeat
```

Write the block into `HEARTBEAT.md` automatically:

```bash
bash ./script.sh setup-heartbeat --write
```

### Queue a task

```bash
bash ./script.sh add "Publish skill to GitHub and ClawHub" \
  --task-type publish \
  --owner "Yunzhou" \
  --source "chat:direct" \
  --next-action "Push main to GitHub, then publish a release to ClawHub" \
  --success-criteria "GitHub updated and ClawHub version published"
```

### Split a composite goal into executable steps

```bash
bash ./script.sh plan "Open-source release" \
  --task-type publish \
  --owner "Yunzhou" \
  --source "chat:direct" \
  --steps "Update README; Push GitHub; Publish ClawHub"
```

### Let heartbeat pick work

```bash
bash ./script.sh run-pending --claim
```

If a task exists, the command prints an `EXECUTE_NOW` brief with the task context. If there is no task, it prints `HEARTBEAT_OK`.

### Update task state

```bash
bash ./script.sh block <id> --reason "Need GitHub token"
bash ./script.sh done <id> --note "GitHub pushed and ClawHub published"
bash ./script.sh report <id>
bash ./script.sh cancel <id> --reason "Handled elsewhere"
```

## Data Model

Tasks are stored in `TODO.md` as a Markdown table. This is runtime data, not source code.

```markdown
| id | title | task_type | owner | requester | source | status | deadline | next_action | success_criteria | created_at | updated_at | last_attempt_at | completed_at | result | tags |
|----|-------|-----------|-------|-----------|--------|--------|----------|-------------|------------------|------------|------------|-----------------|--------------|--------|------|
```

## Heartbeat Integration

Add this to `HEARTBEAT.md`:

```bash
bash /path/to/agent-todo/script.sh run-pending --claim
```

Expected behavior:

- no task → `HEARTBEAT_OK`
- running task exists → continue that work first
- otherwise pick the best pending task and output an execution brief
- task blocked → mark with `block`
- task completed → mark with `done`

## Core Commands

```bash
bash ./script.sh doctor
bash ./script.sh setup-heartbeat --write
bash ./script.sh add "Refine release plan" --task-type doc --next-action "Update README and SKILL.md"
bash ./script.sh plan "Release" --task-type publish --steps "Update README; Push GitHub; Publish ClawHub"
bash ./script.sh list --status pending
bash ./script.sh show <id>
bash ./script.sh run-pending --claim
bash ./script.sh start <id>
bash ./script.sh block <id> --reason "Waiting for review"
bash ./script.sh done <id> --note "README updated and pushed"
bash ./script.sh report <id>
bash ./script.sh cancel <id> --reason "No longer needed"
```

## Statuses

| Status | Meaning |
|------|------|
| pending | queued, not started |
| running | currently being worked on |
| blocked | cannot continue without input or dependency |
| done | completed |
| cancelled | intentionally dropped |

## Testing

Run the smoke test:

```bash
bash tests/smoke.sh
```

## License

MIT License
