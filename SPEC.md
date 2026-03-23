# agent-todo Skill Specification

## Overview

`agent-todo` is an OpenClaw skill that automatically tracks follow-up tasks committed during forum discussions and chat conversations. It ensures nothing falls through the cracks by enforcing deadline discipline and owner accountability.

## Core Problem

During collaborative work, agents often say "I'll do X later" in forum replies or chat, but there's no system to:
1. Capture these commitments automatically
2. Remind the owner before deadlines
3. Track completion status
4. Report back to the requester after finishing

## Core Concepts

### TODO Entry Schema

```yaml
- id: auto-generated UUID
  title: "Brief description of the task"
  deadline: "2026-03-23T18:00:00+08:00"  # ISO-8601 with timezone
  owner: "云舟"                              # Agent who committed
  requester: "阿君"                          # Person who needs it done
  source: "forum:#19" | "chat:direct"        # Where it was committed
  status: "pending" | "done" | "overdue" | "cancelled"
  created_at: ISO-8601
  updated_at: ISO-8601
  completed_at: ISO-8601 | null
  notes: "Additional context from the original commit"
  tags: ["feature", "bugfix"]  # optional
```

### Status Transitions

```
pending → done     (owner marks complete)
pending → overdue  (deadline passed without completion)
overdue → done    (owner completes late)
pending → cancelled (owner cancels with reason)
```

## Functionality

### Core Features

#### 1. Add TODO (from command line or hook)

```bash
# Manual add
todo add "Write SPEC.md for agent-todo" --deadline "2026-03-22T12:00" --owner "云舟" --requester "阿君" --source "chat:direct"

# From forum commit (hook-triggered)
todo add "细化需求文档和技术方案" --deadline "2026-03-22T18:00" --owner "云舟" --requester "阿君" --source "forum:#19"
```

#### 2. List TODOs

```bash
# All pending
todo list

# Filter by owner
todo list --owner "云舟"

# Filter by status
todo list --status pending
todo list --status overdue

# Show upcoming (within N hours)
todo list --upcoming 24
```

#### 3. Mark Complete

```bash
todo done <id> --note "SPEC.md 已完成，仓库已初始化"
```

#### 4. Cancel TODO

```bash
todo cancel <id> --reason "需求已由其他agent完成"
```

#### 5. Check Overdue (for heartbeat)

```bash
todo check-overdue
# Returns list of overdue items, formatted for notification
```

#### 6. Report to Requester

When marking done, automatically generates a completion report:

```
✅ [完成汇报] 任务名称
- 完成时间: 2026-03-22 17:30
- 原始需求来自: forum:#19
- 完成备注: SPEC.md 已完成，仓库已初始化

请确认。
```

### Hook Mechanism

The skill supports OpenClaw hooks for automatic TODO capture:

1. **Forum reply hook**: When the agent replies in forum and commits to a follow-up action, the TODO is automatically logged
2. **Heartbeat check**: During heartbeat, check for overdue items and remind the owner

Hook scripts are installed to `~/.openclaw/hooks/agent-todo/` and configured via OpenClaw's hook system.

### Deadline Enforcement

- **< 2h remaining**: Warning flag in list output
- **Overdue**: Status changes to `overdue`, highlighted in heartbeat report
- **Owner contacted**: If overdue > 24h, skill notifies requester directly

### Completion Reporting Workflow

1. Owner runs `todo done <id> --note "..."`
2. Skill generates completion report (markdown)
3. Skill posts report to original source (forum topic or direct message)
4. TODO status → `done`, `completed_at` recorded

## File Structure

```
agent-todo/
├── SKILL.md              # This file
├── script.sh             # Main CLI entry point
├── todo_lib.sh           # Core library functions
├── hooks/
│   ├── post_reply.sh    # Hook: capture TODOs from forum replies
│   └── heartbeat.sh      # Hook: check overdue items during heartbeat
├── todo.sh              # Main todo management script
├── TODO.md              # The TODO database (workspace file)
└── references/
    └── openclaw-hooks.md # Hook installation guide
```

The TODO database (`TODO.md`) lives outside the hook scripts and is intended as runtime data rather than repository source. In this implementation it defaults to the workspace root relative to the skill directory, and can also be overridden via the `TODO_DB` environment variable.

## Technical Approach

### CLI Design

All operations go through `script.sh` which dispatches to `todo.sh`:

```bash
./script.sh add "title" --deadline "..." --owner "..." ...
./script.sh list [--owner X] [--status Y] [--upcoming H]
./script.sh done <id> --note "..."
./script.sh cancel <id> --reason "..."
./script.sh check-overdue
```

### Data Storage

Plain markdown table in `TODO.md`:

```markdown
# agent-todo Database
<!-- Last updated: 2026-03-22T17:30:00+08:00 -->

## TODOs

| id | title | deadline | owner | requester | source | status | created_at | updated_at | completed_at | notes | tags |
|----|-------|----------|-------|-----------|--------|--------|------------|------------|--------------|-------|------|
| abc123 | Write SPEC.md | 2026-03-22T12:00:00+08:00 | 云舟 | 阿君 | forum:#19 | done | 2026-03-22T10:00:00+08:00 | 2026-03-22T17:30:00+08:00 | 2026-03-22T17:30:00+08:00 | | |
```

Using markdown table allows:
- Human readable and editable
- Git-diff friendly
- No external database dependencies

### OpenClaw Integration

1. **Workspace injection**: `TODO.md` path configured in skill metadata
2. **Hook scripts**: Installed to `~/.openclaw/hooks/agent-todo/`
3. **Heartbeat**: Skill's `check-overdue` called during heartbeat cycle
4. **Forum reporting**: Uses `agent-forum` skill's `reply` to post completion reports

## Implementation Priority

### Phase 1: Core CLI (MVP)
- `add`, `list`, `done` commands
- Markdown table storage
- Deadline checking

### Phase 2: Hook Integration
- Forum reply hook for auto-capture
- Heartbeat overdue check

### Phase 3: Reporting
- Completion report generation
- Forum posting integration

## Acceptance Criteria

1. ✅ Agent can add a TODO with deadline via command line
2. ✅ Agent can list pending, overdue, and done TODOs
3. ✅ Agent can mark TODO complete with a completion note
4. ✅ Overdue TODOs are flagged in heartbeat checks
5. ✅ Completion reports can be posted to the original forum topic
6. ✅ All data persisted in `TODO.md` (markdown table)
7. ✅ Skill follows standard SKILL.md format
8. ✅ Hooks reference OpenClaw's hook system
9. ✅ Code is clean, readable, and suitable for open source
