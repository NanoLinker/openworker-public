# OpenWorker Public

OpenWorker 公开部署脚本。

## Bot 一键部署

在目标服务器上执行一行命令，即可部署一个 OpenWorker Bot（Worker 容器）：

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/openworker-bot-install.sh | \
  GHCR_TOKEN=ghp_xxx \
  WORKER_ID=1 \
  MODEL_PROVIDER=custom MODEL_ID=MiniMax-M2.5 MODEL_NAME=MiniMax \
  MODEL_API_KEY=sk-xxx MODEL_BASE_URL=https://xxx/v1 \
  TZ=Asia/Shanghai \
  DINGTALK_CLIENT_ID=xxx DINGTALK_CLIENT_SECRET=xxx \
  DINGTALK_ROBOT_CODE=xxx DINGTALK_CORP_ID=xxx \
  bash
```

重复执行同一命令 = 升级（拉新镜像 + 更新环境变量 + 保留数据）。

### 必填参数

| 参数 | 说明 |
|------|------|
| `GHCR_TOKEN` | GitHub PAT（需 `read:packages` 权限） |
| `WORKER_ID` | 全局唯一 Worker 标识 |
| `MODEL_PROVIDER` | 模型提供商（如 `custom`） |
| `MODEL_ID` | 模型标识（如 `MiniMax-M2.5`） |
| `MODEL_NAME` | 模型显示名称（如 `MiniMax`） |
| `MODEL_API_KEY` | 模型 API Key |
| `MODEL_BASE_URL` | 模型 API 地址 |
| `TZ` | 时区（如 `Asia/Shanghai`） |
| `DINGTALK_CLIENT_ID` | 钉钉应用 Client ID |
| `DINGTALK_CLIENT_SECRET` | 钉钉应用 Client Secret |
| `DINGTALK_ROBOT_CODE` | 钉钉机器人 Code |
| `DINGTALK_CORP_ID` | 钉钉企业 Corp ID |

### 可选参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `MODEL_CONTEXT_WINDOW` | `204800` | 上下文窗口大小 |
| `MODEL_MAX_TOKENS` | `196608` | 最大输出 token |
| `DATA_DIR` | `/data/openworker` | 持久化数据目录 |
| `CLEAN` | - | 设为 `1` 清理数据目录后重新部署 |
| `SKILL_WHITELIST` | - | Skill 白名单，逗号分隔 |
| `BROWSER_CDP_URL` | - | 远程浏览器 CDP 地址 |
| `SEARXNG_URL` | - | SearXNG 搜索引擎地址 |
| `OPENCLAW_GATEWAY_TOKEN` | - | Gateway 认证 Token |

### 前置条件

- 服务器能访问 `ghcr.io`（拉取镜像）
- 如未安装 Docker，脚本会自动安装

### 脚本执行流程

```
1. 检查必填参数（12 个全检，缺一则报错退出）
2. 检查 Docker（未安装则自动安装，未运行则启动）
3. 登录 GHCR
4. 判断新建 or 升级（通过 Docker label 识别已有容器）
5. 拉取最新镜像
6. 如果升级：读取旧端口 → 停旧容器 → 用新参数重建
7. 如果新建：自动分配端口 → 创建数据目录
8. 启动容器
9. 等待 gateway 就绪（最多 60 秒）
10. 输出部署结果
```

### 升级

重新执行同一命令即可。脚本会自动拉取最新镜像、保留数据目录和端口、用新参数重建容器。

### 卸载

```bash
docker stop openworker-bot-<WORKER_ID> && docker rm openworker-bot-<WORKER_ID>
# 如需清除数据：
rm -rf /data/openworker/<WORKER_ID>
```

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
  SERVER_URL=http://your-server:3000 DEPLOY_ID=<id> AGENT_KEY=<key> bash
```

### 参数说明

| 参数 | 必填 | 说明 |
|------|------|------|
| `SERVER_URL` | 是 | 管理端地址 |
| `DEPLOY_ID` | 是 | 部署 ID（管理端分配） |
| `AGENT_KEY` | 是 | Agent 认证密钥（`ow_` 前缀） |
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
