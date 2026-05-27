# 从旧 LLM cron 迁移

旧版 `status-board-keepalive` cron 会周期性触发 OpenClaw agentTurn。即使 payload 很短，每次 tick 也可能重新注入 system prompt、工具 schema、所有 skills 和若干轮工具调用历史，导致后台保活消耗大量 token。

v6.3 的长期正确做法是：

1. 禁用旧 OpenClaw LLM cron。
2. 安装 `scripts/status_board_keepalive.sh`。
3. 用系统 cron / 平台 scheduler 每 30 分钟运行脚本。

## 需要检查的位置

检查这两个文件中是否存在 `jobId` 为 `status-board-keepalive` 的 job：

```text
/workspace/projects/cron/jobs.json
/workspace/projects/workspace/cron/jobs.json
```

如果存在，删除该 job 或把它的 `enabled` 改为 `false`。保留同一 `jobs` 数组里的其他 job。

## 不要再复制的文件

仓库里的 `keepalive-cron-job.json` 现在只保留为弃用标记，不能再追加到 OpenClaw cron 配置。

## 迁移后验证

确认旧 LLM cron 不再运行：

```bash
grep -R '"jobId"[[:space:]]*:[[:space:]]*"status-board-keepalive"' /workspace/projects/cron /workspace/projects/workspace/cron
```

如果仍能搜到，确认它已经被删除或 `enabled` 为 `false`。

确认零 token 脚本在运行：

```bash
tail -n 50 /workspace/projects/logs/status-board-keepalive.log
```

成功日志示例：

```text
HEARTBEAT status=ok http_code=200 agent_id=...
```

确认模型调用日志里不再出现 `trigger=cron` 的 `status-board-keepalive` agentTurn。平台如果有用量面板，也应该看到后台心跳不再产生 input tokens。
