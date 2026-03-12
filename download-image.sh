#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenWorker Image Download Script
#
# 从阿里云 OSS 下载镜像并 docker load。
#
# Usage:
#   curl -sSL <url>/download-image.sh | \
#     OSS_ACCESS_KEY_ID=xxx OSS_ACCESS_KEY_SECRET=xxx bash
#
#   # 下载特殊 AI 员工镜像
#   curl -sSL <url>/download-image.sh | \
#     IMAGE_NAME=openworker-alaclaw \
#     OSS_ACCESS_KEY_ID=xxx OSS_ACCESS_KEY_SECRET=xxx bash
#
#   # 强制重新下载
#   curl -sSL <url>/download-image.sh | \
#     FORCE=1 OSS_ACCESS_KEY_ID=xxx OSS_ACCESS_KEY_SECRET=xxx bash
# ============================================================

IMAGE_NAME="${IMAGE_NAME:-openworker}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
OSS_BUCKET="openworker"

# ── Helper ────────────────────────────────────────────
die() { echo "错误：$1" >&2; exit 1; }

# ── 1. 检查必填参数 ───────────────────────────────────
if [ -z "${OSS_ACCESS_KEY_ID:-}" ] || [ -z "${OSS_ACCESS_KEY_SECRET:-}" ]; then
  echo "缺少必填参数：OSS_ACCESS_KEY_ID 和 OSS_ACCESS_KEY_SECRET"
  echo ""
  echo "用法："
  echo "  curl -sSL <url>/download-image.sh | \\"
  echo "    OSS_ACCESS_KEY_ID=<id> OSS_ACCESS_KEY_SECRET=<secret> bash"
  echo ""
  echo "参数："
  echo "  OSS_ACCESS_KEY_ID       阿里云 AccessKey ID（必填）"
  echo "  OSS_ACCESS_KEY_SECRET   阿里云 AccessKey Secret（必填）"
  echo "  IMAGE_NAME              镜像名称（默认 openworker）"
  echo "  IMAGE_TAG               镜像标签（默认 latest，自动解析为实际版本号）"
  echo "  FORCE=1                 强制重新下载（即使本地已有相同版本）"
  exit 1
fi

# ── 2. 检查 Docker ───────────────────────────────────
if ! command -v docker &>/dev/null; then
  if [ "$(uname -s)" = "Linux" ]; then
    echo "Docker 未安装，正在安装..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    echo "Docker 安装完成。"
  else
    die "Docker 未安装。macOS 请先安装 Docker Desktop：brew install --cask docker"
  fi
elif ! docker info &>/dev/null; then
  if [ "$(uname -s)" = "Linux" ]; then
    echo "Docker 未运行，正在启动..."
    systemctl start docker
  else
    die "Docker 未运行。请先启动 Docker Desktop。"
  fi
fi

# ── 3. 安装 ossutil ──────────────────────────────────
if ! command -v ossutil &>/dev/null && ! command -v ossutil64 &>/dev/null; then
  echo "安装 ossutil..."
  curl -sL https://gosspublic.alicdn.com/ossutil/install.sh | sudo bash
fi
OSSUTIL_CMD=$(command -v ossutil || command -v ossutil64)

# ── 4. 检测 OSS 内网/公网 ────────────────────────────
OSS_INTERNAL="oss-cn-hangzhou-internal.aliyuncs.com"
OSS_PUBLIC="oss-cn-hangzhou.aliyuncs.com"

if curl -s --connect-timeout 2 "https://${OSS_BUCKET}.${OSS_INTERNAL}" -o /dev/null 2>/dev/null; then
  OSS_ENDPOINT="$OSS_INTERNAL"
  echo "检测到阿里云内网，使用内网 Endpoint"
else
  OSS_ENDPOINT="$OSS_PUBLIC"
  echo "使用公网 Endpoint"
fi

OSS_OPTS=(-e "$OSS_ENDPOINT" -i "$OSS_ACCESS_KEY_ID" -k "$OSS_ACCESS_KEY_SECRET")

# ── 5. 获取版本号 ────────────────────────────────────
OSS_BASE="oss://${OSS_BUCKET}/docker/${IMAGE_NAME}"

if [ "$IMAGE_TAG" = "latest" ]; then
  echo "读取最新版本号..."
  REMOTE_VERSION=$($OSSUTIL_CMD cat "${OSS_BASE}/version.txt" "${OSS_OPTS[@]}" 2>/dev/null | head -1 | tr -d '[:space:]')
  if [ -z "$REMOTE_VERSION" ]; then
    die "无法读取版本号：${OSS_BASE}/version.txt"
  fi
  ACTUAL_TAG="$REMOTE_VERSION"
  TAG_LATEST=true
  echo "  最新版本：$REMOTE_VERSION"
else
  ACTUAL_TAG="$IMAGE_TAG"
  TAG_LATEST=false
fi

# ── 6. 检查本地是否已有 ──────────────────────────────
FULL_IMAGE="${IMAGE_NAME}:${ACTUAL_TAG}"

if [ "${FORCE:-}" != "1" ] && docker image inspect "$FULL_IMAGE" &>/dev/null; then
  echo ""
  echo "本地已有镜像 $FULL_IMAGE，跳过下载。"
  docker images "$FULL_IMAGE" --format "  镜像: {{.Repository}}:{{.Tag}}  ID: {{.ID}}  大小: {{.Size}}  创建: {{.CreatedSince}}"
  echo ""
  echo "如需强制重新下载，请设置 FORCE=1"
  exit 0
fi

# ── 7. 下载镜像 ──────────────────────────────────────
TMP_FILE="/tmp/${IMAGE_NAME}-latest.tar.gz"
echo ""
echo "下载镜像 ${IMAGE_NAME} (${ACTUAL_TAG})..."

$OSSUTIL_CMD cp "${OSS_BASE}/latest.tar.gz" "$TMP_FILE" "${OSS_OPTS[@]}" --force

# ── 8. docker load + 打 tag ──────────────────────────
echo ""
echo "加载镜像到 Docker..."
LOAD_OUTPUT=$(docker load < "$TMP_FILE" 2>&1)
echo "$LOAD_OUTPUT"
rm -f "$TMP_FILE"

# 解析 docker load 输出的镜像名
LOADED_IMAGE=$(echo "$LOAD_OUTPUT" | sed -n 's/.*Loaded image: //p' | head -1)
if [ -z "$LOADED_IMAGE" ]; then
  LOADED_IMAGE=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep "nanolinker/${IMAGE_NAME}" | head -1)
fi

if [ -z "$LOADED_IMAGE" ]; then
  die "docker load 未能识别镜像名称"
fi

# 打版本 tag
if [ "$LOADED_IMAGE" != "$FULL_IMAGE" ]; then
  docker tag "$LOADED_IMAGE" "$FULL_IMAGE"
fi

# 打 latest tag
if [ "$TAG_LATEST" = true ]; then
  docker tag "$LOADED_IMAGE" "${IMAGE_NAME}:latest"
fi

# ── 9. 显示结果 ──────────────────────────────────────
echo ""
echo "=== 下载完成 ==="
echo ""
docker images "$IMAGE_NAME" --format "  {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}"
