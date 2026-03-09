#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/nanolinker/openworker-agent:latest"
CONTAINER_NAME="openworker-agent"
SERVER_URL="${SERVER_URL:?请设置 SERVER_URL，例如 SERVER_URL=http://your-server:3000}"
OPENCLAW_DATA_DIR="${OPENCLAW_DATA_DIR:-/data/openworker}"
REPORT_INTERVAL="${REPORT_INTERVAL:-60000}"

# ── 检查参数 ──────────────────────────────────────────
if [ -z "${HOST_ID:-}" ] || [ -z "${HOST_KEY:-}" ] || [ -z "${SERVER_URL:-}" ]; then
  echo "用法："
  echo "  curl -sSL <url>/install.sh | SERVER_URL=http://x.x.x.x:3000 HOST_ID=<id> HOST_KEY=<key> bash"
  echo ""
  echo "必填参数："
  echo "  SERVER_URL  管理端地址"
  echo "  HOST_ID   Server 分配的主机 ID"
  echo "  HOST_KEY   Host 认证密钥（hk_ 前缀）"
  echo ""
  echo "可选参数："
  echo "  OPENCLAW_DATA_DIR  OpenClaw 数据目录（默认 /data/openworker）"
  echo "  REPORT_INTERVAL    上报间隔毫秒（默认 60000）"
  exit 1
fi

# ── 检查并安装 Docker ─────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "未检测到 Docker，正在自动安装..."
  if command -v apt-get &>/dev/null; then
    apt-get update -y && apt-get install -y docker.io
  elif command -v yum &>/dev/null; then
    yum install -y docker
  elif command -v dnf &>/dev/null; then
    dnf install -y docker
  else
    echo "错误：无法自动安装 Docker，请手动安装后重试"
    exit 1
  fi
  systemctl enable docker
  systemctl start docker
  echo "Docker 安装完成"
fi

if ! docker info &>/dev/null; then
  echo "Docker daemon 未运行，正在启动..."
  systemctl start docker
  sleep 2
  if ! docker info &>/dev/null; then
    echo "错误：Docker daemon 启动失败"
    exit 1
  fi
fi

echo "=== OpenWorker Agent 部署 ==="
echo "  镜像：$IMAGE"
echo "  Server：$SERVER_URL"
echo "  Host ID：$HOST_ID"
echo "  数据目录：$OPENCLAW_DATA_DIR"
echo ""

# ── 清理旧容器 ────────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "停止并删除旧容器..."
  docker stop "$CONTAINER_NAME" 2>/dev/null || true
  docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# ── 拉取最新镜像 ──────────────────────────────────────
# 清除可能干扰的 Docker Hub 凭证配置（避免交互式登录提示）
if [ -f ~/.docker/config.json ]; then
  sed -i 's/"credsStore"[^,}]*[,]\?//' ~/.docker/config.json 2>/dev/null || true
fi
echo "拉取最新镜像..."
docker pull "$IMAGE"

# ── 启动容器 ──────────────────────────────────────────
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
  "$IMAGE"

# ── 验证 ──────────────────────────────────────────────
echo ""
echo "等待启动..."
sleep 3

if docker ps --filter "name=${CONTAINER_NAME}" --filter "status=running" -q | grep -q .; then
  echo "=== 部署成功 ==="
  echo ""
  docker logs "$CONTAINER_NAME" 2>&1 | tail -10
else
  echo "=== 部署失败 ==="
  echo "容器日志："
  docker logs "$CONTAINER_NAME" 2>&1 | tail -20
  exit 1
fi
