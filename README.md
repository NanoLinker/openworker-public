# OpenWorker Public

OpenWorker 公开部署脚本。支持 V1（OpenClaw 引擎）和 V2（OpenCode 引擎）两个版本。

## 镜像下载

从阿里云 OSS 下载镜像并 `docker load`，自动检测内网/公网、读取最新版本号、跳过已有版本。

### 下载 V1 镜像（OpenClaw）

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/download-image.sh | \
  OSS_ACCESS_KEY_ID=xxx OSS_ACCESS_KEY_SECRET=xxx bash
```

### 下载 V2 镜像（OpenCode）

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/download-image.sh | \
  IMAGE_NAME=openworker-v2 \
  OSS_ACCESS_KEY_ID=xxx OSS_ACCESS_KEY_SECRET=xxx bash
```

### 参数

| 参数 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `OSS_ACCESS_KEY_ID` | 是 | - | 阿里云 AccessKey ID |
| `OSS_ACCESS_KEY_SECRET` | 是 | - | 阿里云 AccessKey Secret |
| `IMAGE_NAME` | 否 | `openworker` | 镜像名称（V2 用 `openworker-v2`） |
| `IMAGE_TAG` | 否 | `latest` | 镜像标签，`latest` 自动解析为实际版本号 |
| `FORCE` | 否 | - | 设为 `1` 强制重新下载 |

---

## V1 与 V2 对比

| | V1 (OpenClaw) | V2 (OpenCode) |
|---|---|---|
| 引擎 | OpenClaw | OpenCode |
| 镜像 | `openworker` | `openworker-v2` |
| 部署脚本 | `install-bot.sh` | `install-bot-v2.sh` |
| 镜像大小 | ~2GB | ~150MB |
| 最低配置 | 2C/2GB | 0.5C/512MB |
| LLM | 单模型 | 多模型（Claude/OpenAI/Gemini/本地） |
| 必填参数 | 7 个 + 渠道 | 5 个 |
| 通道 | 钉钉/飞书（必选一个） | Hub（内置）+ 钉钉/飞书（可选） |
| 数据路径 | `/home/node/.openclaw` | `/app/data` |
| 监控端口 | 18790 | 4096（HTTP API） |
| 数据备份 | 多目录 | 单目录 `/app/data` |

两个版本可以在同一台机器上并行运行，互不干扰。

---

## Bot 一键部署（V2 推荐）

### V2 部署（OpenCode 引擎）

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/install-bot-v2.sh | \
  WORKER_ID=ow-abc123 \
  OPENWORKER_KEY=bill-xxx \
  OPENWORKER_URL=https://api.aigcit.com/v1 \
  HUB_URL=https://hub.aigcit.com \
  TZ=Asia/Shanghai \
  bash
```

重复执行同一命令 = 升级（更新环境变量 + 保留数据）。

#### V2 必填参数

| 参数 | 说明 |
|------|------|
| `WORKER_ID` | 全局唯一 Worker 标识 |
| `OPENWORKER_KEY` | Gateway API Key |
| `OPENWORKER_URL` | Gateway API URL（含 /v1） |
| `HUB_URL` | Hub Server 地址 |
| `TZ` | 时区（如 `Asia/Shanghai`） |

#### V2 可选参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `IMAGE_NAME` | `openworker-v2` | 镜像名称 |
| `IMAGE_TAG` | `latest` | 镜像标签 |
| `DATA_DIR` | `/data/openworker` | 持久化数据目录 |
| `SESSION_MODE` | `multi` | 会话模式（`multi`=per-sender 隔离，`single`=共享） |
| `CONTAINER_CPUS` | 不限 | CPU 限制（如 `0.5`） |
| `CONTAINER_MEMORY` | 不限 | 内存限制（如 `512m`） |
| `CLEAN` | - | 设为 `1` 清理数据后重新部署 |

#### V2 数据备份

所有数据在 `$DATA_DIR/$WORKER_ID/` 一个目录内：

```
$DATA_DIR/$WORKER_ID/        ← 备份这个目录即可
├── opencode.db               # Session 历史、消息、tool 调用
├── hub-adapter.db            # Cron 任务、路由状态
├── opencode.json             # 配置
├── AGENTS.md                 # Agent 人设
├── MEMORY.md                 # Agent 记忆
├── HEARTBEAT.md              # Agent 待办
├── .hub-worker-token         # Hub 注册 token
└── .opencode-password        # API 访问密码
```

```bash
# 备份
cp -r /data/openworker/$WORKER_ID backup/

# 还原
cp -r backup/ /data/openworker/$WORKER_ID
docker restart openworker-bot-$WORKER_ID
```

#### V2 监控 API

部署后可通过 HTTP API 监控容器内 Agent 状态：

```bash
# 获取密码
PASSWORD=$(docker exec openworker-bot-$WORKER_ID cat /app/data/.opencode-password)

# 健康检查
curl -u opencode:$PASSWORD http://HOST:PORT/global/health

# 查看 Session 列表
curl -u opencode:$PASSWORD http://HOST:PORT/session

# 查看对话详情
curl -u opencode:$PASSWORD http://HOST:PORT/session/{id}/message
```

---

### V1 部署（OpenClaw 引擎）

> V1 仍然支持，适用于已有钉钉/飞书渠道集成的场景。

#### 飞书

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/install-bot.sh | \
  WORKER_ID=ow-abc123 \
  MODEL_PROVIDER=custom MODEL_ID=MiniMax-M2.5 MODEL_NAME=MiniMax \
  MODEL_API_KEY=sk-xxx MODEL_BASE_URL=https://xxx/v1 \
  TZ=Asia/Shanghai \
  FEISHU_APP_ID=cli_xxx FEISHU_APP_SECRET=xxx \
  bash
```

#### 钉钉

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/install-bot.sh | \
  WORKER_ID=ow-abc123 \
  MODEL_PROVIDER=custom MODEL_ID=MiniMax-M2.5 MODEL_NAME=MiniMax \
  MODEL_API_KEY=sk-xxx MODEL_BASE_URL=https://xxx/v1 \
  TZ=Asia/Shanghai \
  DINGTALK_CLIENT_ID=xxx DINGTALK_CLIENT_SECRET=xxx \
  DINGTALK_ROBOT_CODE=xxx DINGTALK_CORP_ID=xxx \
  bash
```

#### V1 必填参数

| 参数 | 说明 |
|------|------|
| `WORKER_ID` | 全局唯一 Worker 标识 |
| `MODEL_PROVIDER` | 模型提供商（如 `custom`） |
| `MODEL_ID` | 模型标识（如 `MiniMax-M2.5`） |
| `MODEL_NAME` | 模型显示名称 |
| `MODEL_API_KEY` | 模型 API Key |
| `MODEL_BASE_URL` | 模型 API 地址 |
| `TZ` | 时区 |

渠道参数（至少一组）：钉钉 4 个或飞书 2 个。

#### V1 可选参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `IMAGE_NAME` | `openworker` | 镜像名称 |
| `IMAGE_TAG` | `latest` | 镜像标签 |
| `MODEL_CONTEXT_WINDOW` | `204800` | 上下文窗口大小 |
| `MODEL_MAX_TOKENS` | `196608` | 最大输出 token |
| `DATA_DIR` | `/data/openworker` | 持久化数据目录 |
| `CLEAN` | - | 设为 `1` 清理数据后重新部署 |
| `CONTAINER_CPUS` | 不限 | CPU 限制 |
| `CONTAINER_MEMORY` | 不限 | 内存限制 |

---

## 常用命令

| 操作 | 命令 |
|------|------|
| 查看日志 | `docker logs -f openworker-bot-<WORKER_ID>` |
| 重启 | `docker restart openworker-bot-<WORKER_ID>` |
| 进入容器 | `docker exec -it openworker-bot-<WORKER_ID> sh` |
| 卸载 | `docker stop openworker-bot-<WORKER_ID> && docker rm openworker-bot-<WORKER_ID>` |
| 清除数据 | `rm -rf /data/openworker/<WORKER_ID>` |

### 排查问题

```bash
# 查看所有由脚本管理的容器
docker ps -a --filter "label=openworker.managed-by"

# V1 容器
docker ps -a --filter "label=openworker.managed-by=openworker-bot-install"

# V2 容器
docker ps -a --filter "label=openworker.managed-by=openworker-bot-install-v2"
```

---

## Agent 监控一键部署

在目标服务器上执行：

> 前提：服务器上已预装 Docker 镜像（通过 `download-image.sh` 下载 `openworker-agent`）。

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/install-agent.sh | \
  SERVER_URL=http://your-server:3000 HOST_ID=<id> HOST_KEY=<key> bash
```

Monitor Agent 同时支持 V1 和 V2 容器的监控，自动识别引擎类型。

### 参数

| 参数 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `SERVER_URL` | 是 | - | 管理端地址 |
| `HOST_ID` | 是 | - | 主机 ID |
| `HOST_KEY` | 是 | - | Host 认证密钥（`hk_` 前缀） |
| `IMAGE_NAME` | 否 | `openworker-agent` | 镜像名称 |
| `IMAGE_TAG` | 否 | `latest` | 镜像标签 |
