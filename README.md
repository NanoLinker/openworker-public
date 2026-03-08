# OpenWorker Public

OpenWorker 公开部署脚本。

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

重新执行同一命令即可，脚本会自动停止旧容器、拉取新镜像、启动新容器。

### 卸载

```bash
docker stop openworker-agent && docker rm openworker-agent
```
