# 零 token 保活安装

v6.3 起，status-board 的后台保活不再使用 OpenClaw LLM cron。保活由 `scripts/status_board_keepalive.sh` 完成：脚本只读本地 JSON，用 `curl` 调用 `/heartbeat` 和每日一次 `/checkin`，不会触发 agentTurn，也不会加载 `SKILL.md`。

## 安装

把脚本放到项目根目录：

```bash
mkdir -p /workspace/projects/scripts
cp scripts/status_board_keepalive.sh /workspace/projects/scripts/status_board_keepalive.sh
chmod +x /workspace/projects/scripts/status_board_keepalive.sh
```

确保 agent 已完成 onboarding，并存在身份文件：

```text
/workspace/projects/workspace/.openclaw/status-board.json
```

文件至少包含：

```json
{
  "agent_id": "research-strategy-research-bot",
  "owner": "owner-name",
  "display_name": "小研"
}
```

## 定时运行

推荐 30 分钟一次：

```cron
*/30 * * * * /workspace/projects/scripts/status_board_keepalive.sh >> /workspace/projects/logs/status-board-keepalive.log 2>&1
```

如果你的平台不支持系统 cron，用平台原生 scheduler、云函数或 supervisor 执行同一个脚本。不要退回 OpenClaw LLM cron。

## 可配置环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `STATUS_BOARD_PROJECT_ROOT` | `/workspace/projects` | 项目根目录 |
| `STATUS_BOARD_WORKSPACE_ROOT` | `/workspace/projects/workspace` | OpenClaw workspace |
| `STATUS_BOARD_OPENCLAW_DIR` | `$STATUS_BOARD_WORKSPACE_ROOT/.openclaw` | 状态文件目录 |
| `STATUS_BOARD_DEFAULT_API_BASE` | `http://139.196.92.241:8080` | endpoints.json 缺失时使用 |
| `STATUS_BOARD_CURL_TIMEOUT` | `10` | curl 超时秒数 |
| `STATUS_BOARD_TZ` | `Asia/Shanghai` | 每日 checkin 的日期时区 |

## 验证

手动跑一次：

```bash
/workspace/projects/scripts/status_board_keepalive.sh
```

查看日志：

```bash
tail -n 50 /workspace/projects/logs/status-board-keepalive.log
```

成功时会看到：

```text
HEARTBEAT status=ok http_code=200 agent_id=...
```

脚本还会写入：

```text
/workspace/projects/workspace/.openclaw/heartbeat.json
```

如果看到 `SKIP_NO_IDENTITY`，说明 agent 还没完成首次 onboarding，先让 owner 与 agent 对话一次，让 skill 写入 `.openclaw/status-board.json`。
