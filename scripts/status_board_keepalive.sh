#!/usr/bin/env bash

set -u

PROJECT_ROOT="${STATUS_BOARD_PROJECT_ROOT:-/workspace/projects}"
WORKSPACE_ROOT="${STATUS_BOARD_WORKSPACE_ROOT:-$PROJECT_ROOT/workspace}"
OPENCLAW_DIR="${STATUS_BOARD_OPENCLAW_DIR:-$WORKSPACE_ROOT/.openclaw}"
LOG_DIR="${STATUS_BOARD_LOG_DIR:-$PROJECT_ROOT/logs}"
LOG_FILE="${STATUS_BOARD_LOG_FILE:-$LOG_DIR/status-board-keepalive.log}"
IDENTITY_FILE="${STATUS_BOARD_IDENTITY_FILE:-$OPENCLAW_DIR/status-board.json}"
ENDPOINTS_FILE="${STATUS_BOARD_ENDPOINTS_FILE:-$OPENCLAW_DIR/endpoints.json}"
HEARTBEAT_FILE="${STATUS_BOARD_HEARTBEAT_FILE:-$OPENCLAW_DIR/heartbeat.json}"
LAST_CHECKIN_FILE="${STATUS_BOARD_LAST_CHECKIN_FILE:-$OPENCLAW_DIR/last_checkin_day.txt}"
DEFAULT_API_BASE="${STATUS_BOARD_DEFAULT_API_BASE:-http://139.196.92.241:8080}"
TIMEZONE="${STATUS_BOARD_TZ:-Asia/Shanghai}"
CURL_TIMEOUT="${STATUS_BOARD_CURL_TIMEOUT:-10}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
CURL_BIN="${CURL_BIN:-curl}"

mkdir -p "$OPENCLAW_DIR" "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG_FILE"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "ERROR missing_command command=$1"
    exit 1
  fi
}

need_cmd "$PYTHON_BIN"
need_cmd "$CURL_BIN"

if [ ! -f "$IDENTITY_FILE" ]; then
  log "SKIP_NO_IDENTITY identity_file=$IDENTITY_FILE"
  exit 0
fi

identity_info="$("$PYTHON_BIN" - "$IDENTITY_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as exc:
    print(f"ERROR\t{exc}\t\t")
    sys.exit(0)

agent_id = str(data.get("agent_id") or "").strip()
owner = str(data.get("owner") or "").strip()
display_name = str(data.get("display_name") or agent_id).strip()
if not agent_id:
    print("ERROR\tmissing agent_id\t\t")
else:
    print("\x1f".join(["OK", agent_id, owner, display_name]))
PY
)"

IFS=$'\037' read -r identity_status agent_id owner display_name <<< "$identity_info"
if [ "$identity_status" != "OK" ]; then
  log "SKIP_BAD_IDENTITY reason=${agent_id:-unknown}"
  exit 0
fi

api_base="$("$PYTHON_BIN" - "$ENDPOINTS_FILE" "$DEFAULT_API_BASE" <<'PY'
import json
import sys

path, default = sys.argv[1], sys.argv[2]
api_base = default
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    api_base = str(data.get("api_base") or default).strip() or default
except FileNotFoundError:
    pass
except Exception:
    pass
print(api_base.rstrip("/"))
PY
)"

tmp_dir="${TMPDIR:-/tmp}"
heartbeat_body="$(mktemp "$tmp_dir/status-board-heartbeat.XXXXXX")"
checkin_body="$(mktemp "$tmp_dir/status-board-checkin.XXXXXX")"
response_body="$(mktemp "$tmp_dir/status-board-response.XXXXXX")"
cleanup() {
  rm -f "$heartbeat_body" "$checkin_body" "$response_body"
}
trap cleanup EXIT

"$PYTHON_BIN" - "$heartbeat_body" "$agent_id" "$owner" "$display_name" <<'PY'
import json
import sys

path, agent_id, owner, display_name = sys.argv[1:5]
body = {
    "agent_id": agent_id,
    "owner": owner,
    "display_name": display_name,
    "event": "heartbeat",
    "status": "active",
    "source": "status-board-keepalive",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(body, f, ensure_ascii=False, separators=(",", ":"))
PY

post_json() {
  endpoint="$1"
  body_file="$2"
  http_code="$("$CURL_BIN" -sS -m "$CURL_TIMEOUT" -o "$response_body" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -X POST \
    --data @"$body_file" \
    "$api_base$endpoint" 2>>"$LOG_FILE")"
  curl_status=$?
  if [ "$curl_status" -ne 0 ]; then
    http_code="000"
  fi
  printf '%s' "$http_code"
}

heartbeat_code="$(post_json "/heartbeat" "$heartbeat_body")"
heartbeat_status="error"
case "$heartbeat_code" in
  2*) heartbeat_status="ok" ;;
esac

"$PYTHON_BIN" - "$HEARTBEAT_FILE" "$heartbeat_status" "$heartbeat_code" "$api_base" "$agent_id" <<'PY'
import json
import sys
from datetime import datetime, timezone

path, status, http_code, api_base, agent_id = sys.argv[1:6]
data = {
    "last_heartbeat_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "status": status,
    "http_code": http_code,
    "api_base": api_base,
    "agent_id": agent_id,
    "source": "status_board_keepalive.sh",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

log "HEARTBEAT status=$heartbeat_status http_code=$heartbeat_code agent_id=$agent_id api_base=$api_base"

today="$(TZ="$TIMEZONE" date '+%Y-%m-%d')"
last_checkin=""
if [ -f "$LAST_CHECKIN_FILE" ]; then
  last_checkin="$(tr -d '[:space:]' < "$LAST_CHECKIN_FILE" 2>/dev/null || true)"
fi

if [ "$last_checkin" != "$today" ]; then
  "$PYTHON_BIN" - "$checkin_body" "$agent_id" "$owner" "$display_name" <<'PY'
import json
import sys

path, agent_id, owner, display_name = sys.argv[1:5]
name = display_name or agent_id
body = {
    "agent_id": agent_id,
    "owner": owner,
    "display_name": display_name,
    "event": "checkin",
    "status": "active",
    "message": f"{name} 自动心跳打卡",
    "source": "status-board-keepalive",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(body, f, ensure_ascii=False, separators=(",", ":"))
PY
  checkin_code="$(post_json "/checkin" "$checkin_body")"
  case "$checkin_code" in
    2*)
      printf '%s\n' "$today" > "$LAST_CHECKIN_FILE"
      log "CHECKIN status=ok http_code=$checkin_code agent_id=$agent_id day=$today"
      ;;
    *)
      log "CHECKIN status=error http_code=$checkin_code agent_id=$agent_id day=$today"
      ;;
  esac
fi
