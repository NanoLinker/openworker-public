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

### 脚本执行流程

```
开始
 │
 ├─ 检查参数（SERVER_URL、DEPLOY_ID、AGENT_KEY 缺一则报错退出）
 │
 ├─ 检查 Docker（未安装或 daemon 未运行则报错退出）
 │
 ├─ 检测已有容器
 │   └─ 如果已存在 openworker-agent 容器 → 自动停止并删除
 │
 ├─ 拉取最新镜像（ghcr.io/nanolinker/openworker-agent:latest）
 │
 ├─ 启动新容器（挂载 docker.sock、/proc、/sys、数据目录）
 │
 └─ 等待 3 秒验证
     ├─ 容器运行中 → 输出"部署成功"+ 最近日志
     └─ 容器未运行 → 输出"部署失败"+ 错误日志
```

因此该脚本可以安全地**重复执行**——首次运行是全新部署，再次运行等同于升级（停旧容器 → 拉新镜像 → 启新容器）。

### 升级

重新执行同一命令即可：

```bash
curl -sSL https://raw.githubusercontent.com/NanoLinker/openworker-public/main/install-agent.sh | \
  SERVER_URL=http://your-server:3000 DEPLOY_ID=<id> AGENT_KEY=<key> bash
```

脚本会自动停止旧容器、拉取最新镜像、启动新容器。

### 卸载

```bash
docker stop openworker-agent && docker rm openworker-agent
```

### 排查问题

```bash
# 查看容器状态
docker ps -a --filter name=openworker-agent

# 查看最近日志
docker logs --tail 20 openworker-agent

# 查看实时日志
docker logs -f openworker-agent
```
