#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenWorker V2 Bot One-Click Deploy Script
#
# Uses OpenCode engine + Hub communication.
# Requires local Docker image (pre-loaded via docker load).
#
# Usage:
#   curl -sSL <url>/install-bot-v2.sh | \
#     WORKER_ID=ow-abc123 \
#     OPENWORKER_KEY=bill-xxx \
#     OPENWORKER_URL=https://api.aigcit.com/v1 \
#     HUB_URL=https://hub.aigcit.com \
#     TZ=Asia/Shanghai \
#     bash
#
# Re-run the same command to upgrade (update env + keep data).
# ============================================================

IMAGE_NAME="${IMAGE_NAME:-openworker-v2}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
DATA_DIR="${DATA_DIR:-/data/openworker}"
CONTAINER_CPUS="${CONTAINER_CPUS:-}"
CONTAINER_MEMORY="${CONTAINER_MEMORY:-}"
CONTAINER_MEMORY_SWAP="${CONTAINER_MEMORY_SWAP:-}"

# ── Helper ────────────────────────────────────────────
die() { echo "错误：$1" >&2; exit 1; }

# ── 1. 检查必填参数 ───────────────────────────────────
REQUIRED_VARS=(
  WORKER_ID
  OPENWORKER_KEY
  OPENWORKER_URL
  HUB_URL
  TZ
)

missing=()
for var in "${REQUIRED_VARS[@]}"; do
  [ -z "${!var:-}" ] && missing+=("$var")
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "缺少必填参数：${missing[*]}"
  echo ""
  echo "用法："
  echo "  curl -sSL <url>/install-bot-v2.sh | \\"
  echo "    WORKER_ID=<id> \\"
  echo "    OPENWORKER_KEY=<key> \\"
  echo "    OPENWORKER_URL=https://api.aigcit.com/v1 \\"
  echo "    HUB_URL=https://hub.aigcit.com \\"
  echo "    TZ=Asia/Shanghai \\"
  echo "    bash"
  echo ""
  echo "必填参数（5 个）："
  echo "  WORKER_ID          全局唯一 Worker 标识"
  echo "  OPENWORKER_KEY     Gateway API Key"
  echo "  OPENWORKER_URL     Gateway API URL（含 /v1）"
  echo "  HUB_URL            Hub Server URL"
  echo "  TZ                 时区（如 Asia/Shanghai）"
  echo ""
  echo "可选参数："
  echo "  IMAGE_NAME              镜像名称（默认 openworker-v2）"
  echo "  IMAGE_TAG               镜像标签（默认 latest）"
  echo "  DATA_DIR                持久化数据目录（默认 /data/openworker）"
  echo "  CLEAN=1                 清理数据目录后重新部署"
  echo "  SESSION_MODE            会话模式（multi=per-sender，single=共享，默认 multi）"
  echo "  CONTAINER_CPUS          CPU 限制（如 0.5）"
  echo "  CONTAINER_MEMORY        内存限制（如 512m）"
  echo "  CONTAINER_MEMORY_SWAP   内存+Swap 限制"
  echo "  READY_TIMEOUT           等待容器就绪秒数（默认 180）"
  exit 1
fi

CONTAINER_NAME="openworker-bot-${WORKER_ID}"

echo "=== OpenWorker V2 Bot 部署 ==="
echo "  Worker ID：$WORKER_ID"
echo "  容器名：$CONTAINER_NAME"
echo "  镜像：$IMAGE"
echo "  引擎：OpenCode"
echo "  渠道：Hub"
echo "  数据目录：$DATA_DIR/$WORKER_ID"
echo ""

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
  die "本地未找到镜像 $IMAGE，请先手动下载并 docker load。"
fi

# 架构检查
HOST_ARCH=$(uname -m)
IMAGE_ARCH=$(docker inspect "$IMAGE" --format '{{.Architecture}}' 2>/dev/null || true)
case "$HOST_ARCH" in
  x86_64)  EXPECTED_ARCH="amd64" ;;
  aarch64) EXPECTED_ARCH="arm64" ;;
  arm64)   EXPECTED_ARCH="arm64" ;;
  *)       EXPECTED_ARCH="" ;;
esac
if [ -n "$EXPECTED_ARCH" ] && [ -n "$IMAGE_ARCH" ] && [ "$IMAGE_ARCH" != "$EXPECTED_ARCH" ]; then
  die "镜像架构不匹配：本机 $HOST_ARCH ($EXPECTED_ARCH)，镜像 $IMAGE_ARCH"
fi

# 磁盘空间检查（至少 2GB 可用）
AVAIL_KB=$(df -k / | awk 'NR==2{print $4}')
MIN_KB=$((2 * 1024 * 1024))
if [ "$AVAIL_KB" -lt "$MIN_KB" ] 2>/dev/null; then
  AVAIL_GB=$(awk "BEGIN{printf \"%.1f\", $AVAIL_KB/1024/1024}")
  die "磁盘空间不足：剩余 ${AVAIL_GB}GB，至少需要 2GB"
fi

echo "本地镜像："
docker images "$IMAGE" --format "  镜像: {{.Repository}}:{{.Tag}}  ID: {{.ID}}  大小: {{.Size}}  创建: {{.CreatedSince}}"

# ── 4. 判断新建 or 升级 ──────────────────────────────
EXISTING=$(docker ps -a --filter "label=openworker.worker-id=$WORKER_ID" --format '{{.Names}}' | head -1)
PORT=""

if [ -n "$EXISTING" ]; then
  echo "检测到已有容器：$EXISTING（升级模式）"
  PORT=$(docker inspect "$EXISTING" --format '{{(index (index .NetworkSettings.Ports "4096/tcp") 0).HostPort}}' 2>/dev/null || true)
  if [ -n "$PORT" ]; then
    echo "  保留端口：$PORT"
  else
    echo "  旧容器无端口映射，新容器交给 docker 自动分配"
  fi
fi

# ── 5. CLEAN 模式 ────────────────────────────────────
if [ "${CLEAN:-}" = "1" ]; then
  echo "CLEAN 模式：清理数据目录 $DATA_DIR/$WORKER_ID"
  rm -rf "${DATA_DIR:?}/${WORKER_ID:?}"
fi

# ── 6. 停止旧容器（升级模式）─────────────────────────
if [ -n "$EXISTING" ]; then
  echo "停止并删除旧容器..."
  docker stop "$EXISTING" 2>/dev/null || true
  docker rm "$EXISTING" 2>/dev/null || true
fi

# ── 7. 创建数据目录 ──────────────────────────────────
# 端口由 docker daemon 自分配（详见步骤 8 的 -p "4096"），
# 这样并行部署也不会撞，主机上其他服务占的端口也自动避开。

mkdir -p "$DATA_DIR/$WORKER_ID"
if $IS_LINUX; then
  chown -R 1000:1000 "$DATA_DIR/$WORKER_ID"
fi

# ── 8. 构建 docker run 参数 ──────────────────────────
IMAGE_SHA=$(docker inspect --format '{{.Id}}' "$IMAGE" | cut -c8-19)

# 升级模式保留旧端口；新建模式让 docker 自分配（避免端口扫描的 race condition）
if [ -n "$PORT" ]; then
  PORT_ARG="${PORT}:4096"
else
  PORT_ARG="4096"
fi

RUN_ARGS=(
  -d
  --name "$CONTAINER_NAME"
  --restart unless-stopped
  ${CONTAINER_CPUS:+--cpus "$CONTAINER_CPUS"}
  ${CONTAINER_MEMORY:+--memory "$CONTAINER_MEMORY"}
  ${CONTAINER_MEMORY_SWAP:+--memory-swap "$CONTAINER_MEMORY_SWAP"}
  --label "openworker.worker-id=$WORKER_ID"
  --label "openworker.managed-by=openworker-bot-install-v2"
  --label "openworker.version=$IMAGE_SHA"
  --label "openworker.engine=opencode"
  -p "$PORT_ARG"
  -v "$DATA_DIR/$WORKER_ID:/openworker/data"
  -e "WORKER_ID=$WORKER_ID"
  -e "TZ=$TZ"
  -e "OPENWORKER_KEY=$OPENWORKER_KEY"
  -e "OPENWORKER_URL=$OPENWORKER_URL"
  -e "HUB_URL=$HUB_URL"
)

[ -n "${SESSION_MODE:-}" ] && RUN_ARGS+=(-e "SESSION_MODE=$SESSION_MODE")

# ── 9. 启动容器 ─────────────────────────────────────
echo "启动容器..."
docker run "${RUN_ARGS[@]}" "$IMAGE"

# 新建模式：从 docker 拿真实分配的 host port
if [ -z "$PORT" ]; then
  PORT=$(docker port "$CONTAINER_NAME" 4096/tcp | head -1 | awk -F: '{print $NF}')
  echo "  分配端口：$PORT（由 docker daemon 自动分配）"
fi

# ── 10. 等待就绪 ─────────────────────────────────────
# Default 180s — first-time OpenCode boot + Hub WS registration on a slow
# network often takes 60-120s; 60s timeout was too tight and caused admin
# to mark deploys as failed even though the container would become ready
# moments later. Override via READY_TIMEOUT env var.
echo ""
echo "等待 OpenCode 就绪..."
TIMEOUT="${READY_TIMEOUT:-180}"
ELAPSED=0
READY=false

while [ $ELAPSED -lt $TIMEOUT ]; do
  # Readiness signals emitted by the V2 entrypoint + openworker plugin:
  #   - "OpenCode ready" — HTTP server accepting requests
  #   - "WS ... connected" — worker has connected to the Hub
  #   - "Hub registration complete" — worker is reachable
  # Any one of these means the container is up enough to dispatch to.
  if docker logs "$CONTAINER_NAME" 2>&1 | grep -qE "OpenCode ready|WS +. +connected|Hub registration complete"; then
    READY=true
    break
  fi

  if ! docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" -q | grep -q .; then
    echo ""
    echo "=== 部署失败 ==="
    echo "容器已退出，日志："
    docker logs "$CONTAINER_NAME" 2>&1 | tail -30
    exit 1
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
  printf "."
done
echo ""

# ── 11. 验证结果 ─────────────────────────────────────
if $READY; then
  echo "=== 部署成功 ==="
  echo ""
  echo "  容器名：$CONTAINER_NAME"
  echo "  端口：$PORT（OpenCode HTTP API）"
  echo "  引擎：OpenCode"
  echo "  渠道：Hub"
  echo "  数据目录：$DATA_DIR/$WORKER_ID"
  echo "  镜像版本：$IMAGE_SHA"

  IMG_VER=$(docker exec "$CONTAINER_NAME" cat /openworker/image/manifest.json 2>/dev/null || echo "未知")
  OC_VER=$(docker exec "$CONTAINER_NAME" opencode --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "未知")
  echo "  OpenWorker 版本：$IMG_VER"
  echo "  OpenCode 版本：$OC_VER"

  # SOUL.md preview (user-editable persona supplement in the workspace volume)
  SOUL_PREVIEW=$(docker exec "$CONTAINER_NAME" head -3 /openworker/data/workspace/SOUL.md 2>/dev/null || true)
  if [ -n "$SOUL_PREVIEW" ]; then
    echo ""
    echo "Bot 人格预览（SOUL.md）："
    echo "$SOUL_PREVIEW" | while read -r line; do
      echo "  $line"
    done || true
  fi

  echo ""
  echo "常用命令："
  echo "  查看日志：docker logs -f $CONTAINER_NAME"
  echo "  重启：docker restart $CONTAINER_NAME"
  echo "  进入容器：docker exec -it $CONTAINER_NAME sh"
  echo "  停止容器：docker stop $CONTAINER_NAME"
  echo "  卸载：docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
  echo "  清除数据：rm -rf $DATA_DIR/$WORKER_ID"
  echo ""
  echo "监控 API："
  # V2 entrypoint hardcodes the server password — no file to read.
  OC_PASS="openworker-local"
  echo "  Health: curl -u opencode:$OC_PASS http://<host>:$PORT/global/health"
  echo "  Sessions: curl -u opencode:$OC_PASS http://<host>:$PORT/session"
else
  echo "=== 部署超时 ==="
  echo "OpenCode 未在 ${TIMEOUT} 秒内就绪，但容器仍在运行。"
  echo "请手动检查日志：docker logs -f $CONTAINER_NAME"
  echo ""
  echo "最近日志："
  docker logs "$CONTAINER_NAME" 2>&1 | tail -20
  exit 1
fi
