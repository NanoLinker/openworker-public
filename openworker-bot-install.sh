#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenWorker Bot One-Click Deploy Script
#
# Supports DingTalk, Feishu, or both channels.
# Supports two image sources: GHCR (international) or Aliyun OSS (China).
#
# Usage (GHCR + Feishu):
#   curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/openworker-bot-install.sh | \
#     GHCR_TOKEN=ghp_xxx \
#     WORKER_ID=ow-abc123 \
#     MODEL_PROVIDER=custom MODEL_ID=MiniMax-M2.5 MODEL_NAME=MiniMax \
#     MODEL_API_KEY=sk-xxx MODEL_BASE_URL=https://xxx/v1 \
#     TZ=Asia/Shanghai \
#     FEISHU_APP_ID=cli_xxx FEISHU_APP_SECRET=xxx \
#     bash
#
# Usage (OSS + DingTalk, faster in China):
#   curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/openworker-bot-install.sh | \
#     OSS_ACCESS_KEY_ID=LTAI5xxx OSS_ACCESS_KEY_SECRET=xxx \
#     WORKER_ID=ow-abc123 \
#     MODEL_PROVIDER=custom MODEL_ID=MiniMax-M2.5 MODEL_NAME=MiniMax \
#     MODEL_API_KEY=sk-xxx MODEL_BASE_URL=https://xxx/v1 \
#     TZ=Asia/Shanghai \
#     DINGTALK_CLIENT_ID=xxx DINGTALK_CLIENT_SECRET=xxx \
#     DINGTALK_ROBOT_CODE=xxx DINGTALK_CORP_ID=xxx \
#     bash
#
# Re-run the same command to upgrade (pull new image + update env + keep data).
# ============================================================

IMAGE="ghcr.io/nanolinker/openworker:latest"
DATA_DIR="${DATA_DIR:-/data/openworker}"
MODEL_CONTEXT_WINDOW="${MODEL_CONTEXT_WINDOW:-204800}"
MODEL_MAX_TOKENS="${MODEL_MAX_TOKENS:-196608}"

# OSS defaults
OSS_BUCKET="${OSS_BUCKET:-openworker}"

# ── Helper ────────────────────────────────────────────
die() { echo "错误：$1" >&2; exit 1; }

# ── 1. 检查镜像来源 ──────────────────────────────────
HAS_OSS=false
HAS_GHCR=false

if [ -n "${OSS_ACCESS_KEY_ID:-}" ] && [ -n "${OSS_ACCESS_KEY_SECRET:-}" ]; then
  HAS_OSS=true
fi
if [ -n "${GHCR_TOKEN:-}" ]; then
  HAS_GHCR=true
fi

# ── 2. 检查必填参数 ───────────────────────────────────
REQUIRED_VARS=(
  WORKER_ID
  MODEL_PROVIDER MODEL_ID MODEL_NAME MODEL_API_KEY MODEL_BASE_URL
  TZ
)

missing=()
for var in "${REQUIRED_VARS[@]}"; do
  [ -z "${!var:-}" ] && missing+=("$var")
done

# Image source check
if [ "$HAS_OSS" = false ] && [ "$HAS_GHCR" = false ]; then
  missing+=("IMAGE_SOURCE(需要 GHCR_TOKEN 或 OSS_ACCESS_KEY_ID+OSS_ACCESS_KEY_SECRET)")
fi

# Channel check: at least one channel must be configured
HAS_DINGTALK=false
HAS_FEISHU=false

if [ -n "${DINGTALK_CLIENT_ID:-}" ] && [ -n "${DINGTALK_CLIENT_SECRET:-}" ] && \
   [ -n "${DINGTALK_ROBOT_CODE:-}" ] && [ -n "${DINGTALK_CORP_ID:-}" ]; then
  HAS_DINGTALK=true
fi

if [ -n "${FEISHU_APP_ID:-}" ] && [ -n "${FEISHU_APP_SECRET:-}" ]; then
  HAS_FEISHU=true
fi

if [ "$HAS_DINGTALK" = false ] && [ "$HAS_FEISHU" = false ]; then
  missing+=("CHANNEL(至少配置一个渠道: 钉钉或飞书)")
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "缺少必填参数：${missing[*]}"
  echo ""
  echo "用法（GHCR + 飞书）："
  echo "  curl -sSL <url>/openworker-bot-install.sh | \\"
  echo "    GHCR_TOKEN=ghp_xxx \\"
  echo "    WORKER_ID=<id> \\"
  echo "    MODEL_PROVIDER=custom MODEL_ID=<model> MODEL_NAME=<name> \\"
  echo "    MODEL_API_KEY=<key> MODEL_BASE_URL=<url> \\"
  echo "    TZ=Asia/Shanghai \\"
  echo "    FEISHU_APP_ID=cli_xxx FEISHU_APP_SECRET=<secret> \\"
  echo "    bash"
  echo ""
  echo "用法（OSS + 钉钉，国内更快）："
  echo "  curl -sSL <url>/openworker-bot-install.sh | \\"
  echo "    OSS_ACCESS_KEY_ID=<id> OSS_ACCESS_KEY_SECRET=<secret> \\"
  echo "    WORKER_ID=<id> \\"
  echo "    MODEL_PROVIDER=custom MODEL_ID=<model> MODEL_NAME=<name> \\"
  echo "    MODEL_API_KEY=<key> MODEL_BASE_URL=<url> \\"
  echo "    TZ=Asia/Shanghai \\"
  echo "    DINGTALK_CLIENT_ID=<id> DINGTALK_CLIENT_SECRET=<secret> \\"
  echo "    DINGTALK_ROBOT_CODE=<code> DINGTALK_CORP_ID=<corp_id> \\"
  echo "    bash"
  echo ""
  echo "必填参数（7 个）："
  echo "  WORKER_ID               全局唯一 Worker 标识"
  echo "  MODEL_PROVIDER          模型提供商（如 custom）"
  echo "  MODEL_ID                模型标识（如 MiniMax-M2.5）"
  echo "  MODEL_NAME              模型显示名称（如 MiniMax）"
  echo "  MODEL_API_KEY           模型 API Key"
  echo "  MODEL_BASE_URL          模型 API 地址"
  echo "  TZ                      时区（如 Asia/Shanghai）"
  echo ""
  echo "镜像来源（二选一）："
  echo "  GHCR（国际）:"
  echo "    GHCR_TOKEN              GitHub PAT（read:packages 权限）"
  echo "  阿里云 OSS（国内更快）:"
  echo "    OSS_ACCESS_KEY_ID       阿里云 AccessKey ID"
  echo "    OSS_ACCESS_KEY_SECRET   阿里云 AccessKey Secret"
  echo ""
  echo "渠道参数（至少配置一组）："
  echo "  钉钉:"
  echo "    DINGTALK_CLIENT_ID      钉钉应用 Client ID"
  echo "    DINGTALK_CLIENT_SECRET  钉钉应用 Client Secret"
  echo "    DINGTALK_ROBOT_CODE     钉钉机器人 Code"
  echo "    DINGTALK_CORP_ID        钉钉企业 Corp ID"
  echo "  飞书:"
  echo "    FEISHU_APP_ID           飞书应用 App ID"
  echo "    FEISHU_APP_SECRET       飞书应用 App Secret"
  echo ""
  echo "可选参数："
  echo "  MODEL_CONTEXT_WINDOW    上下文窗口大小（默认 204800）"
  echo "  MODEL_MAX_TOKENS        最大输出 token（默认 196608）"
  echo "  DATA_DIR                持久化数据目录（默认 /data/openworker）"
  echo "  OSS_BUCKET              OSS Bucket 名称（默认 openworker）"
  echo "  OSS_ENDPOINT            OSS Endpoint（自动检测内外网，一般不需要填）"
  echo "  CLEAN=1                 清理数据目录后重新部署"
  echo "  SKILL_WHITELIST         Skill 白名单，逗号分隔"
  echo "  BROWSER_CDP_URL         远程浏览器 CDP 地址"
  echo "  SEARXNG_URL             SearXNG 搜索引擎地址"
  echo "  OPENCLAW_GATEWAY_TOKEN  Gateway 认证 Token"
  exit 1
fi

CONTAINER_NAME="openworker-bot-${WORKER_ID}"

# Determine image source display
if [ "$HAS_OSS" = true ]; then
  IMAGE_SOURCE_DISPLAY="阿里云 OSS ($OSS_ENDPOINT)"
else
  IMAGE_SOURCE_DISPLAY="GHCR (ghcr.io)"
fi

# Build channel display string
CHANNELS=""
[ "$HAS_DINGTALK" = true ] && CHANNELS="钉钉"
[ "$HAS_FEISHU" = true ] && CHANNELS="${CHANNELS:+$CHANNELS + }飞书"

echo "=== OpenWorker Bot 部署 ==="
echo "  Worker ID：$WORKER_ID"
echo "  容器名：$CONTAINER_NAME"
echo "  模型：$MODEL_ID ($MODEL_NAME)"
echo "  渠道：$CHANNELS"
echo "  镜像来源：$IMAGE_SOURCE_DISPLAY"
echo "  数据目录：$DATA_DIR/$WORKER_ID"
echo ""

# ── 3. 检查 Docker ───────────────────────────────────
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

# ── 4. 判断新建 or 升级 ──────────────────────────────
EXISTING=$(docker ps -a --filter "label=openworker.worker-id=$WORKER_ID" --format '{{.Names}}' | head -1)
PORT=""

if [ -n "$EXISTING" ]; then
  echo "检测到已有容器：$EXISTING（升级模式）"

  # Read port from existing container
  PORT=$(docker inspect "$EXISTING" --format '{{(index (index .NetworkSettings.Ports "18790/tcp") 0).HostPort}}' 2>/dev/null || true)
  [ -z "$PORT" ] && PORT="18790"
  echo "  保留端口：$PORT"
fi

# ── 5. 获取镜像 ──────────────────────────────────────
if [ "$HAS_OSS" = true ]; then
  # ── 5a. 从阿里云 OSS 下载镜像 ──────────────────────
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH_NAME="amd64" ;;
    aarch64) ARCH_NAME="arm64" ;;
    arm64)   ARCH_NAME="arm64" ;;
    *)       die "不支持的架构：$ARCH" ;;
  esac

  # Auto-detect OSS endpoint: try internal first (Aliyun VPC), fallback to public
  if [ -z "${OSS_ENDPOINT:-}" ]; then
    OSS_INTERNAL="oss-cn-hangzhou-internal.aliyuncs.com"
    if curl -s --connect-timeout 2 "https://${OSS_BUCKET}.${OSS_INTERNAL}" -o /dev/null 2>/dev/null; then
      OSS_ENDPOINT="$OSS_INTERNAL"
      echo "  检测到阿里云内网，使用内网 Endpoint"
    else
      OSS_ENDPOINT="oss-cn-hangzhou.aliyuncs.com"
      echo "  使用公网 Endpoint"
    fi
  fi

  OSS_OBJECT="docker/openworker-${ARCH_NAME}-latest.tar.gz"
  OSS_URL="https://${OSS_BUCKET}.${OSS_ENDPOINT}/${OSS_OBJECT}"
  TMP_FILE="/tmp/openworker-${ARCH_NAME}-latest.tar.gz"

  echo "从 OSS 下载镜像（${ARCH_NAME}）..."
  echo "  $OSS_URL"

  # Download using ossutil if available, otherwise use curl with signed URL
  if command -v ossutil &>/dev/null || command -v ossutil64 &>/dev/null; then
    OSSUTIL_CMD=$(command -v ossutil || command -v ossutil64)
    $OSSUTIL_CMD cp "oss://${OSS_BUCKET}/${OSS_OBJECT}" "$TMP_FILE" \
      -e "$OSS_ENDPOINT" \
      -i "$OSS_ACCESS_KEY_ID" \
      -k "$OSS_ACCESS_KEY_SECRET" \
      --force
  else
    # Install ossutil
    echo "安装 ossutil..."
    OSSUTIL_ARCH="$ARCH_NAME"
    [ "$OSSUTIL_ARCH" = "arm64" ] && OSSUTIL_ARCH="arm64"
    curl -sSL "https://gosspublic.alicdn.com/ossutil/v2-beta/2.0.3-beta.09171400/ossutil-2.0.3-beta.09171400-linux-${OSSUTIL_ARCH}.zip" -o /tmp/ossutil.zip
    unzip -qo /tmp/ossutil.zip -d /tmp/ossutil-install
    OSSUTIL_CMD=$(find /tmp/ossutil-install -name 'ossutil*' -type f | head -1)
    chmod +x "$OSSUTIL_CMD"

    $OSSUTIL_CMD cp "oss://${OSS_BUCKET}/${OSS_OBJECT}" "$TMP_FILE" \
      -e "$OSS_ENDPOINT" \
      -i "$OSS_ACCESS_KEY_ID" \
      -k "$OSS_ACCESS_KEY_SECRET" \
      --force
  fi

  echo "加载镜像到 Docker..."
  docker load < "$TMP_FILE"
  rm -f "$TMP_FILE"

  # Tag as expected image name for consistency
  LOADED_IMAGE=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'nanolinker/openworker' | head -1)
  if [ -n "$LOADED_IMAGE" ] && [ "$LOADED_IMAGE" != "$IMAGE" ]; then
    docker tag "$LOADED_IMAGE" "$IMAGE"
  fi

  echo "OSS 镜像加载完成。"
else
  # ── 5b. 从 GHCR 拉取镜像 ───────────────────────────
  echo "登录 GHCR..."
  echo "$GHCR_TOKEN" | docker login ghcr.io -u openworker --password-stdin

  echo "拉取最新镜像..."
  docker pull "$IMAGE"
fi

# ── 6. CLEAN 模式 ────────────────────────────────────
if [ "${CLEAN:-}" = "1" ]; then
  echo "CLEAN 模式：清理数据目录 $DATA_DIR/$WORKER_ID"
  rm -rf "${DATA_DIR:?}/${WORKER_ID:?}"
fi

# ── 7. 停止旧容器（升级模式）─────────────────────────
if [ -n "$EXISTING" ]; then
  echo "停止并删除旧容器..."
  docker stop "$EXISTING" 2>/dev/null || true
  docker rm "$EXISTING" 2>/dev/null || true
fi

# ── 8. 新建模式：分配端口 + 创建数据目录 ─────────────
if [ -z "$PORT" ]; then
  # Auto-assign port starting from 18790
  USED_PORTS=$(docker ps -a --filter "label=openworker.worker-id" --format '{{.Ports}}' | grep -oE '0\.0\.0\.0:[0-9]+' | cut -d: -f2 | sort -n || true)
  PORT=18790
  while echo "$USED_PORTS" | grep -q "^${PORT}$"; do
    PORT=$((PORT + 1))
  done
  echo "  分配端口：$PORT"
fi

mkdir -p "$DATA_DIR/$WORKER_ID"
# chown: only needed on Linux (Docker Desktop on macOS handles permissions via VirtioFS)
if $IS_LINUX; then
  chown 1000:1000 "$DATA_DIR/$WORKER_ID"
fi

# ── 9. 构建 docker run 参数 ──────────────────────────
IMAGE_SHA=$(docker inspect --format '{{.Id}}' "$IMAGE" | cut -c8-19)

RUN_ARGS=(
  -d
  --name "$CONTAINER_NAME"
  --restart unless-stopped
  --label "openworker.worker-id=$WORKER_ID"
  --label "openworker.managed-by=openworker-bot-install"
  --label "openworker.version=$IMAGE_SHA"
  -p "${PORT}:18790"
  -v "$DATA_DIR/$WORKER_ID:/home/node/.openclaw"
  -e "WORKER_ID=$WORKER_ID"
  -e "TZ=$TZ"
  -e "MODEL_PROVIDER=$MODEL_PROVIDER"
  -e "MODEL_ID=$MODEL_ID"
  -e "MODEL_NAME=$MODEL_NAME"
  -e "MODEL_API_KEY=$MODEL_API_KEY"
  -e "MODEL_BASE_URL=$MODEL_BASE_URL"
  -e "MODEL_CONTEXT_WINDOW=$MODEL_CONTEXT_WINDOW"
  -e "MODEL_MAX_TOKENS=$MODEL_MAX_TOKENS"
)

# DingTalk channel (only pass if fully configured)
if [ "$HAS_DINGTALK" = true ]; then
  RUN_ARGS+=(
    -e "DINGTALK_CLIENT_ID=$DINGTALK_CLIENT_ID"
    -e "DINGTALK_CLIENT_SECRET=$DINGTALK_CLIENT_SECRET"
    -e "DINGTALK_ROBOT_CODE=$DINGTALK_ROBOT_CODE"
    -e "DINGTALK_CORP_ID=$DINGTALK_CORP_ID"
  )
  [ -n "${DINGTALK_CARD_TEMPLATE_ID:-}" ] && RUN_ARGS+=(-e "DINGTALK_CARD_TEMPLATE_ID=$DINGTALK_CARD_TEMPLATE_ID")
fi

# Feishu channel (only pass if fully configured)
if [ "$HAS_FEISHU" = true ]; then
  RUN_ARGS+=(
    -e "FEISHU_APP_ID=$FEISHU_APP_ID"
    -e "FEISHU_APP_SECRET=$FEISHU_APP_SECRET"
  )
fi

# Optional env vars (only pass if set)
[ -n "${SKILL_WHITELIST:-}" ]         && RUN_ARGS+=(-e "SKILL_WHITELIST=$SKILL_WHITELIST")
[ -n "${BROWSER_CDP_URL:-}" ]         && RUN_ARGS+=(-e "BROWSER_CDP_URL=$BROWSER_CDP_URL")
[ -n "${SEARXNG_URL:-}" ]             && RUN_ARGS+=(-e "SEARXNG_URL=$SEARXNG_URL")
[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]  && RUN_ARGS+=(-e "OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN")

# ── 10. 启动容器 ─────────────────────────────────────
echo "启动容器..."
docker run "${RUN_ARGS[@]}" "$IMAGE"

# ── 11. 等待 gateway 就绪 ────────────────────────────
echo ""
echo "等待 gateway 就绪..."
TIMEOUT=60
ELAPSED=0
READY=false

while [ $ELAPSED -lt $TIMEOUT ]; do
  if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "Gateway.*listening\|Gateway.*started\|listening on.*18789"; then
    READY=true
    break
  fi

  # Check if container is still running
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

# ── 12. 验证结果 ─────────────────────────────────────
if $READY; then
  echo "=== 部署成功 ==="
  echo ""
  echo "  容器名：$CONTAINER_NAME"
  echo "  端口：$PORT"
  echo "  渠道：$CHANNELS"
  echo "  镜像来源：$IMAGE_SOURCE_DISPLAY"
  echo "  数据目录：$DATA_DIR/$WORKER_ID"
  echo "  镜像版本：$IMAGE_SHA"

  # ── 12a. 外置加载详情 ──────────────────────────────
  echo ""
  echo "外置加载情况："

  # Skills
  SKILL_SUMMARY=$(docker logs "$CONTAINER_NAME" 2>&1 | grep "External skills:" | tail -1)
  if [ -n "$SKILL_SUMMARY" ]; then
    echo "  $SKILL_SUMMARY"
    docker logs "$CONTAINER_NAME" 2>&1 | grep -E '^\s*\[OK\]|^\s*\[FAIL\]' | while read -r line; do
      echo "    $line"
    done
  else
    echo "  Skills: 无外置 Skill"
  fi

  # Profile
  PROFILE_LINE=$(docker logs "$CONTAINER_NAME" 2>&1 | grep "External profiles:" | tail -1)
  if [ -n "$PROFILE_LINE" ]; then
    echo "  $PROFILE_LINE"
  else
    echo "  Profile: 使用默认"
  fi

  # Config override
  CONFIG_LINE=$(docker logs "$CONTAINER_NAME" 2>&1 | grep "External config override applied" | tail -1)
  if [ -n "$CONFIG_LINE" ]; then
    echo "  Config override: applied"
  else
    echo "  Config override: 无"
  fi

  # SOUL.md preview
  SOUL_PREVIEW=$(docker exec "$CONTAINER_NAME" head -3 /home/node/.openclaw/workspace/SOUL.md 2>/dev/null)
  if [ -n "$SOUL_PREVIEW" ]; then
    echo ""
    echo "Bot 人格预览："
    echo "$SOUL_PREVIEW" | while read -r line; do
      echo "  $line"
    done
  fi

  # Hint if no external files
  if [ -z "$SKILL_SUMMARY" ] && [ -z "$PROFILE_LINE" ] && [ -z "$CONFIG_LINE" ]; then
    echo ""
    echo "提示：将自定义文件放到以下目录，然后 docker restart $CONTAINER_NAME 即可生效："
    echo "  Skills:  $DATA_DIR/$WORKER_ID/openworker-skills/"
    echo "  Profile: $DATA_DIR/$WORKER_ID/openworker-profiles/main/"
    echo "  Config:  $DATA_DIR/$WORKER_ID/openworker-config/"
  fi

  echo ""
  echo "常用命令："
  echo "  查看日志：docker logs -f $CONTAINER_NAME"
  echo "  重启：docker restart $CONTAINER_NAME"
  echo "  进入容器：docker exec -it $CONTAINER_NAME bash"
  echo "  停止容器：docker stop $CONTAINER_NAME"
  echo "  卸载：docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
  echo "  清除数据：rm -rf $DATA_DIR/$WORKER_ID"
else
  echo "=== 部署超时 ==="
  echo "Gateway 未在 ${TIMEOUT} 秒内就绪，但容器仍在运行。"
  echo "请手动检查日志：docker logs -f $CONTAINER_NAME"
  echo ""
  echo "最近日志："
  docker logs "$CONTAINER_NAME" 2>&1 | tail -20
  exit 1
fi
