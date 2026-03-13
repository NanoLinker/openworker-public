#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenWorker Agent Deploy Script
#
# Requires local Docker image (pre-loaded via download-image.sh).
#
# Usage:
#   curl -sSL <url>/install-agent.sh | \
#     SERVER_URL=http://x.x.x.x:3000 HOST_ID=<id> HOST_KEY=<key> bash
#
# Re-run the same command to upgrade (update env + keep data).
# ============================================================

IMAGE_NAME="${IMAGE_NAME:-openworker-agent}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
CONTAINER_NAME="openworker-agent"
OPENCLAW_DATA_DIR="${OPENCLAW_DATA_DIR:-/data/openworker}"
REPORT_INTERVAL="${REPORT_INTERVAL:-60000}"

# ── Helper ────────────────────────────────────────────
die() { echo "错误：$1" >&2; exit 1; }

# ── 1. 检查参数 ──────────────────────────────────────
if [ -z "${SERVER_URL:-}" ] || [ -z "${HOST_ID:-}" ] || [ -z "${HOST_KEY:-}" ]; then
  echo "用法："
  echo "  curl -sSL <url>/install-agent.sh | \\"
  echo "    SERVER_URL=http://x.x.x.x:3000 HOST_ID=<id> HOST_KEY=<key> bash"
  echo ""
  echo "必填参数："
  echo "  SERVER_URL  管理端地址"
  echo "  HOST_ID     Server 分配的主机 ID"
  echo "  HOST_KEY    Host 认证密钥（hk_ 前缀）"
  echo ""
  echo "可选参数："
  echo "  IMAGE_NAME        镜像名称（默认 openworker-agent）"
  echo "  IMAGE_TAG         镜像标签（默认 latest）"
  echo "  OPENCLAW_DATA_DIR OpenClaw 数据目录（默认 /data/openworker）"
  echo "  REPORT_INTERVAL   上报间隔毫秒（默认 60000）"
  exit 1
fi

# ── 2. 检查 Docker ───────────────────────────────────
IS_LINUX=false
[ "$(uname -s)" = "Linux" ] && IS_LINUX=true

if ! command -v docker &>/dev/null; then
  if $IS_LINUX; then
    echo "Docker 未安装，正在安装..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    echo "Docker 安装完成。"
  else
    die "Docker 未安装。macOS 请先安装 Docker Desktop：brew install --cask docker"
  fi
elif ! docker info &>/dev/null; then
  if $IS_LINUX; then
    echo "Docker 未运行，正在启动..."
    systemctl start docker
  else
    die "Docker 未运行。请先启动 Docker Desktop。"
  fi
fi

# ── 3. 检查本地镜像 ──────────────────────────────────
if ! docker image inspect "$IMAGE" &>/dev/null; then
  die "本地未找到镜像 $IMAGE，请先通过 download-image.sh 下载。"
fi

echo "=== OpenWorker Agent 部署 ==="
echo "  镜像：$IMAGE"
docker images "$IMAGE" --format "  镜像 ID: {{.ID}}  大小: {{.Size}}  创建: {{.CreatedSince}}"
echo "  Server：$SERVER_URL"
echo "  Host ID：$HOST_ID"
echo "  数据目录：$OPENCLAW_DATA_DIR"
echo ""

# ── 4. 清理旧容器 ────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "停止并删除旧容器..."
  docker stop "$CONTAINER_NAME" 2>/dev/null || true
  docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# ── 5. 启动容器 ──────────────────────────────────────
echo "启动容器..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v "${OPENCLAW_DATA_DIR}:${OPENCLAW_DATA_DIR}:ro" \
  -e SERVER_URL="$SERVER_URL" \
  -e HOST_ID="$HOST_ID" \
  -e HOST_KEY="$HOST_KEY" \
  -e REPORT_INTERVAL="$REPORT_INTERVAL" \
  -e OPENCLAW_DATA_DIR="$OPENCLAW_DATA_DIR" \
  -e OPENCLAW_CONTAINER_PATTERN="${OPENCLAW_CONTAINER_PATTERN:-openworker}" \
  "$IMAGE"

# ── 6. 验证 ──────────────────────────────────────────
echo ""
echo "等待启动..."
sleep 3

if docker ps --filter "name=${CONTAINER_NAME}" --filter "status=running" -q | grep -q .; then
  echo "=== 部署成功 ==="
  AGENT_VER=$(docker exec "$CONTAINER_NAME" cat /etc/openworker-version 2>/dev/null || echo "未知")
  echo "  Agent 版本：$AGENT_VER"
  echo ""
  docker logs "$CONTAINER_NAME" 2>&1 | tail -10
  echo ""
  echo "常用命令："
  echo "  查看日志：docker logs -f $CONTAINER_NAME"
  echo "  重启：docker restart $CONTAINER_NAME"
  echo "  卸载：docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
else
  echo "=== 部署失败 ==="
  echo "容器日志："
  docker logs "$CONTAINER_NAME" 2>&1 | tail -20
  exit 1
fi
