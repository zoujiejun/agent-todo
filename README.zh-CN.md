# agent-todo

> **别再让 AI Agent 只会口头答应。**
> 聊天界面很适合对话，却不擅长真正把事情做完。当一个 Agent 说“这个我稍后去做”，上下文窗口一清空，这个承诺往往也就随之消失。
>
> `agent-todo` 是一个为 AI Agent 原生设计的主动执行队列。它不是把事项放进一个被动清单里就结束，而是直接接入 Agent 的 heartbeat——驱动 Agent 自动认领下一项任务、在后台执行，并在完成后回写到原始来源。
>
> 不再只是提醒，而是真正执行。

- GitHub: https://github.com/zoujiejun/agent-todo
- ClawHub: https://clawhub.com/skills/agent-todo
- English README: [README.md](./README.md)

## 新定位

这个 skill 现在是**执行队列**，不是单纯提醒工具。

- heartbeat 的职责是**拿任务并执行**，不是只提醒
- 任务带有 **next_action** 和 **success_criteria**
- 队列状态支持 **pending / running / blocked / done / cancelled**
- `run-pending` 会输出下一条应立即执行的任务简报

## 功能特性

- **任务入队** — 支持 title、type、owner、deadline、next_action、success_criteria
- **heartbeat 认领任务** — 通过 `run-pending --claim` 选择下一条任务
- **执行状态跟踪** — 支持 `pending`、`running`、`blocked`、`done`、`cancelled`
- **按 source 生成汇报** — 可针对 forum / chat 输出不同回写模板
- **保留来源上下文** — 完成后可以回写原 chat / 原 topic
- **reply 自动结构化** — 从回复承诺中生成 task_type、next_action、success_criteria
- **优先续跑 running** — 避免 heartbeat 每次新开坑
- **检查 heartbeat 接入状态** — 提供 `doctor` 和 `setup-heartbeat`

## 与 agent-forum 的关系

`agent-todo` 是一个**独立 skill**，不依赖 `agent-forum`。

- 可以单独当作 agent 执行队列使用
- 也可以接到 OpenClaw 的 heartbeat / reply hook
- 如果已经在用 `agent-forum`，论坛回复可以作为任务来源之一，但只是可选集成

## 快速开始

### 安装

```bash
git clone https://github.com/zoujiejun/agent-todo.git
cd agent-todo
chmod +x todo.sh todo_lib.sh script.sh hooks/*.sh
```

### 初始化

```bash
bash ./script.sh init
```

首次使用时，如果 heartbeat 还没接入，`agent-todo` 会自动提醒。

### 接入 heartbeat

检查当前状态：

```bash
bash ./script.sh doctor
```

查看应写入的 heartbeat block：

```bash
bash ./script.sh setup-heartbeat
```

自动写入 `HEARTBEAT.md`：

```bash
bash ./script.sh setup-heartbeat --write
```

### 添加任务

```bash
bash ./script.sh add "把 skill 发布到 GitHub 和 ClawHub" \
  --task-type publish \
  --owner "云舟" \
  --source "chat:direct" \
  --next-action "先推 GitHub main，再发布 ClawHub 版本" \
  --success-criteria "GitHub 已更新，ClawHub 版本已发布"
```

### 把复合目标拆成步骤

```bash
bash ./script.sh plan "开源发布" \
  --task-type publish \
  --owner "云舟" \
  --source "chat:direct" \
  --steps "更新 README; 推送 GitHub; 发布 ClawHub"
```

### heartbeat 取任务

```bash
bash ./script.sh run-pending --claim
```

如果有任务，命令会输出 `EXECUTE_NOW` 简报；如果没有任务，会输出 `HEARTBEAT_OK`。

### 更新任务状态

```bash
bash ./script.sh block <id> --reason "缺少 GitHub token"
bash ./script.sh done <id> --note "GitHub 已推送，ClawHub 已发布"
bash ./script.sh report <id>
bash ./script.sh cancel <id> --reason "任务已由别处处理"
```

## 数据结构

任务存储在 `TODO.md` 的 Markdown 表格里，属于运行时数据，不是仓库源码。

```markdown
| id | title | task_type | owner | requester | source | status | deadline | next_action | success_criteria | created_at | updated_at | last_attempt_at | completed_at | result | tags |
|----|-------|-----------|-------|-----------|--------|--------|----------|-------------|------------------|------------|------------|-----------------|--------------|--------|------|
```

## Heartbeat 集成

在 `HEARTBEAT.md` 中加入：

```bash
bash /path/to/agent-todo/script.sh run-pending --claim
```

预期行为：

- 没任务 → `HEARTBEAT_OK`
- 有 running → 优先续跑
- 否则挑最合适的 pending 任务
- 做不动 → 用 `block` 标记原因
- 做完 → 用 `done` 写回结果

## 核心命令

```bash
bash ./script.sh doctor
bash ./script.sh setup-heartbeat --write
bash ./script.sh add "细化发布方案" --task-type doc --next-action "更新 README 和 SKILL.md"
bash ./script.sh plan "发布" --task-type publish --steps "更新 README; 推送 GitHub; 发布 ClawHub"
bash ./script.sh list --status pending
bash ./script.sh show <id>
bash ./script.sh run-pending --claim
bash ./script.sh start <id>
bash ./script.sh block <id> --reason "等待 review"
bash ./script.sh done <id> --note "README 已更新并推送"
bash ./script.sh report <id>
bash ./script.sh cancel <id> --reason "已不需要"
```

## 状态说明

| 状态 | 说明 |
|------|------|
| pending | 已入队，未开始 |
| running | 正在执行 |
| blocked | 受阻，需外部条件或输入 |
| done | 已完成 |
| cancelled | 已取消 |

## 测试

运行 smoke test：

```bash
bash tests/smoke.sh
```

## 许可证

MIT License
