# OpenWorker Public

OpenWorker 公开部署脚本。

## Bot 一键部署

在目标服务器上执行一行命令，即可部署一个 OpenWorker Bot（Worker 容器）。支持钉钉、飞书或同时接入两个渠道。支持 GHCR（国际）和阿里云 OSS（国内更快）两种镜像来源。

### GHCR + 飞书

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/openworker-bot-install.sh | \
  GHCR_TOKEN=ghp_xxx \
  WORKER_ID=1 \
  MODEL_PROVIDER=custom MODEL_ID=MiniMax-M2.5 MODEL_NAME=MiniMax \
  MODEL_API_KEY=sk-xxx MODEL_BASE_URL=https://xxx/v1 \
  TZ=Asia/Shanghai \
  FEISHU_APP_ID=cli_xxx FEISHU_APP_SECRET=xxx \
  bash
```

### OSS + 钉钉（国内更快）

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/openworker-bot-install.sh | \
  OSS_ACCESS_KEY_ID=LTAI5xxx OSS_ACCESS_KEY_SECRET=xxx \
  WORKER_ID=1 \
  MODEL_PROVIDER=custom MODEL_ID=MiniMax-M2.5 MODEL_NAME=MiniMax \
  MODEL_API_KEY=sk-xxx MODEL_BASE_URL=https://xxx/v1 \
  TZ=Asia/Shanghai \
  DINGTALK_CLIENT_ID=xxx DINGTALK_CLIENT_SECRET=xxx \
  DINGTALK_ROBOT_CODE=xxx DINGTALK_CORP_ID=xxx \
  bash
```

### OSS + 双渠道（钉钉 + 飞书）

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/openworker-bot-install.sh | \
  OSS_ACCESS_KEY_ID=LTAI5xxx OSS_ACCESS_KEY_SECRET=xxx \
  WORKER_ID=1 \
  MODEL_PROVIDER=custom MODEL_ID=MiniMax-M2.5 MODEL_NAME=MiniMax \
  MODEL_API_KEY=sk-xxx MODEL_BASE_URL=https://xxx/v1 \
  TZ=Asia/Shanghai \
  DINGTALK_CLIENT_ID=xxx DINGTALK_CLIENT_SECRET=xxx \
  DINGTALK_ROBOT_CODE=xxx DINGTALK_CORP_ID=xxx \
  FEISHU_APP_ID=cli_xxx FEISHU_APP_SECRET=xxx \
  bash
```

重复执行同一命令 = 升级（拉新镜像 + 更新环境变量 + 保留数据）。

### 镜像来源（二选一）

| 方式 | 参数 | 说明 |
|------|------|------|
| **GHCR** | `GHCR_TOKEN` | GitHub PAT（需 `read:packages` 权限），国际网络 |
| **阿里云 OSS** | `OSS_ACCESS_KEY_ID` + `OSS_ACCESS_KEY_SECRET` | 国内服务器推荐，自动检测内外网 |

OSS 方式会自动检测服务器架构（amd64/arm64）和网络环境（阿里云内网/公网），无需手动配置。

### 必填参数

| 参数 | 说明 |
|------|------|
| `WORKER_ID` | 全局唯一 Worker 标识 |
| `MODEL_PROVIDER` | 模型提供商（如 `custom`） |
| `MODEL_ID` | 模型标识（如 `MiniMax-M2.5`） |
| `MODEL_NAME` | 模型显示名称（如 `MiniMax`） |
| `MODEL_API_KEY` | 模型 API Key |
| `MODEL_BASE_URL` | 模型 API 地址 |
| `TZ` | 时区（如 `Asia/Shanghai`） |

### 渠道参数（至少配置一组）

**钉钉：**

| 参数 | 说明 |
|------|------|
| `DINGTALK_CLIENT_ID` | 钉钉应用 Client ID |
| `DINGTALK_CLIENT_SECRET` | 钉钉应用 Client Secret |
| `DINGTALK_ROBOT_CODE` | 钉钉机器人 Code |
| `DINGTALK_CORP_ID` | 钉钉企业 Corp ID |

**飞书：**

| 参数 | 说明 |
|------|------|
| `FEISHU_APP_ID` | 飞书应用 App ID（`cli_` 前缀） |
| `FEISHU_APP_SECRET` | 飞书应用 App Secret |

### 可选参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `MODEL_CONTEXT_WINDOW` | `204800` | 上下文窗口大小 |
| `MODEL_MAX_TOKENS` | `196608` | 最大输出 token |
| `DATA_DIR` | `/data/openworker` | 持久化数据目录 |
| `OSS_BUCKET` | `openworker` | OSS Bucket 名称 |
| `OSS_ENDPOINT` | 自动检测 | OSS Endpoint（一般不需要填） |
| `CLEAN` | - | 设为 `1` 清理数据目录后重新部署 |
| `SKILL_WHITELIST` | - | Skill 白名单，逗号分隔 |
| `BROWSER_CDP_URL` | - | 远程浏览器 CDP 地址 |
| `SEARXNG_URL` | - | SearXNG 搜索引擎地址 |
| `OPENCLAW_GATEWAY_TOKEN` | - | Gateway 认证 Token |
| `DINGTALK_CARD_TEMPLATE_ID` | - | 钉钉 AI 卡片模板 ID |

### 前置条件

- 如未安装 Docker，脚本会自动安装
- GHCR 方式需要服务器能访问 `ghcr.io`
- OSS 方式需要阿里云 AccessKey（只需 OSS 读权限）

### 部署后输出

脚本部署完成后会自动显示：

- 外置 Skill 加载状态（名称 + [OK]/[FAIL]）
- Profile 加载状态
- 配置覆盖状态
- Bot 人格预览（SOUL.md 前 3 行）
- 如无外置文件，提示文件放置路径

### 自定义 Skill / Profile

部署完成后，将自定义文件放到数据目录：

```
$DATA_DIR/$WORKER_ID/
├── openworker-skills/        # 自定义 Skill
│   └── my-skill/
│       └── SKILL.md
├── openworker-profiles/      # 自定义 Profile
│   └── main/
│       └── SOUL.md
└── openworker-config/        # 配置覆盖
    └── openclaw.json
```

然后 `docker restart openworker-bot-<WORKER_ID>` 即可生效。

详细开发教程见 [openworker-bot-dev-starter](https://github.com/NanoLinker/openworker-bot-dev-starter)。

### 脚本执行流程

```
1. 检查必填参数（7 个基础 + 镜像来源 + 至少一组渠道参数）
2. 检查 Docker（未安装则自动安装，未运行则启动）
3. 获取镜像：
   - OSS 方式：自动检测架构和网络 → 下载 tar.gz → docker load
   - GHCR 方式：登录 GHCR → docker pull
4. 判断新建 or 升级（通过 Docker label 识别已有容器）
5. 如果升级：读取旧端口 → 停旧容器 → 用新参数重建
6. 如果新建：自动分配端口 → 创建数据目录
7. 启动容器
8. 等待 gateway 就绪（最多 60 秒）
9. 输出部署结果 + 外置加载详情
```

### 升级

重新执行同一命令即可。脚本会自动拉取最新镜像、保留数据目录和端口、用新参数重建容器。

### 常用命令

| 操作 | 命令 |
|------|------|
| 查看日志 | `docker logs -f openworker-bot-<WORKER_ID>` |
| 重启 | `docker restart openworker-bot-<WORKER_ID>` |
| 进入容器 | `docker exec -it openworker-bot-<WORKER_ID> bash` |
| 卸载 | `docker stop openworker-bot-<WORKER_ID> && docker rm openworker-bot-<WORKER_ID>` |
| 清除数据 | `rm -rf /data/openworker/<WORKER_ID>` |

### 排查问题

```bash
# 查看所有由脚本管理的容器
docker ps -a --filter "label=openworker.managed-by=openworker-bot-install"

# 查看日志
docker logs --tail 20 openworker-bot-<WORKER_ID>
docker logs -f openworker-bot-<WORKER_ID>
```

---

## Agent 一键部署

在目标服务器上执行：

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/install-agent.sh | \
  SERVER_URL=http://your-server:3000 HOST_ID=<id> HOST_KEY=<key> bash
```

### 参数说明

| 参数 | 必填 | 说明 |
|------|------|------|
| `SERVER_URL` | 是 | 管理端地址 |
| `HOST_ID` | 是 | 主机 ID（管理端分配） |
| `HOST_KEY` | 是 | Host 认证密钥（`hk_` 前缀） |
| `OPENCLAW_DATA_DIR` | 否 | OpenClaw 数据目录（默认 `/data/openworker`） |
| `REPORT_INTERVAL` | 否 | 上报间隔毫秒（默认 `60000`） |

### 前置条件

- 已安装 Docker 且 daemon 正在运行
- 服务器能访问 `ghcr.io`（拉取镜像）和管理端地址（上报数据）

### 升级

重新执行同一命令即可。

### 卸载

```bash
docker stop openworker-agent && docker rm openworker-agent
```

### 排查问题

```bash
docker ps -a --filter name=openworker-agent
docker logs --tail 20 openworker-agent
docker logs -f openworker-agent
```
