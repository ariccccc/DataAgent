# DataAgent 阿里云云效流水线部署说明

本文档详细说明如何将 DataAgent 项目通过阿里云云效（DevOps）流水线部署到阿里云 ECS 服务器，实现从代码提交到自动构建、自动部署的完整 CI/CD 流程。

---

## 快速开始（步骤概览）

1. **前置准备**：创建 ECS、安装 Docker/Docker Compose、配置云效主机组、准备 API Key
2. **创建流水线**：新建流水线 → 配置代码源 → 添加「构建」任务（执行 `build-deploy-package.sh`）→ 添加「主机部署」任务（解压并执行 `docker compose build && up -d`）
3. **运行流水线**：触发构建与部署，访问 `http://<ECS公网IP>:3000` 验证

详细步骤见下文各章节。

---

## 一、项目概述

### 1.1 技术栈

| 组件 | 技术 | 说明 |
|------|------|------|
| 后端 | Java 17 + Spring Boot 3.4.8 + Spring AI Alibaba | 智能数据分析 API 服务，端口 8065 |
| 前端 | Vue 3 + Vite + Element Plus | Web 管理界面，端口 3000 |
| 业务数据库 | MySQL 8.0 | 存储智能体配置、模型配置等（nl2sql_db） |
| 模拟数据源 | MySQL 8.0 + PostgreSQL 15 | 演示用业务数据（product_db、china_population_db） |

### 1.2 部署架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    阿里云 ECS 服务器                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │  Frontend   │  │   Backend   │  │  MySQL / PostgreSQL     │  │
│  │  (Nginx)    │──│  (Spring)   │──│  (业务库 + 模拟数据源)     │  │
│  │  :3000      │  │  :8065      │  │  (容器内网)               │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
│         │                  │                                      │
│         └──────────────────┴── Docker Compose 统一编排            │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 部署方式说明

本项目支持两种云效流水线部署方式：

| 方式 | 适用场景 | 构建时间 | 部署复杂度 |
|------|----------|----------|------------|
| **方式一：部署包 + Docker Compose** | 推荐，适合大多数场景 | 较长（首次构建） | 低 |
| **方式二：Docker 镜像 + 主机部署** | 需要多环境复用镜像时 | 中等 | 中 |

---

## 二、前置准备

### 2.1 阿里云资源准备

完成以下资源的创建与配置：

| 资源 | 说明 | 操作入口 |
|------|------|----------|
| **阿里云账号** | 开通云效、ECS、容器镜像服务 ACR | [阿里云控制台](https://www.aliyun.com) |
| **ECS 实例** | 建议 4 核 8G 及以上，系统盘 40GB+ | 云服务器 ECS |
| **安全组** | 放行 22(SSH)、3000、8065 端口 | ECS 安全组 |
| **代码仓库** | 将项目推送到 Codeup 或绑定 GitHub/GitLab | 云效 Codeup |
| **容器镜像服务 ACR** | 用于存储 Docker 镜像（方式二需要） | 容器镜像服务 |

### 2.2 ECS 服务器环境准备

在目标 ECS 上执行以下操作：

```bash
# 1. 安装 Docker（若未安装）
curl -fsSL https://get.docker.com | sh
sudo systemctl start docker
sudo systemctl enable docker

# 2. 安装 Docker Compose v2
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker compose version  # 验证

# 3. 配置 Docker 镜像加速（国内必做，否则拉取镜像很慢）
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://registry.cn-hangzhou.aliyuncs.com"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 2.3 云效主机组配置

1. 登录 [云效控制台](https://devops.aliyun.com)
2. 进入 **企业设置** → **主机组管理** → **新建主机组**
3. 选择 **阿里云 ECS** 或 **自有主机**
4. 若为 ECS：按标签或实例 ID 添加机器
5. 若为自有主机：在主机上执行云效提供的安装脚本，将主机接入
6. 确保主机组内机器已安装 Docker 和 Docker Compose

### 2.4 敏感信息准备（生产环境必做）

以下信息需在云效 **变量与缓存** 中配置为 **加密变量**：

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `AI_DASHSCOPE_API_KEY` | 通义千问 API Key（或您使用的模型 Key） | sk-xxx |
| `MYSQL_ROOT_PASSWORD` | MySQL root 密码（若需自定义） | your_secure_password |
| `DATA_AGENT_DATASOURCE_PASSWORD` | 业务库密码（若与 root 不同） | your_db_password |

---

## 三、方式一：部署包 + Docker Compose（推荐）

此方式在流水线构建阶段生成部署包（zip），部署阶段在主机上解压后执行 `docker compose build` 和 `docker compose up`。

### 3.1 创建流水线

1. 进入云效 **Flow** → **流水线** → **新建流水线**
2. 选择 **空白流水线** 或从模板创建

### 3.2 配置流水线源

1. 在 **流水线源** 阶段：
   - **代码源**：选择您的代码仓库（Codeup / GitHub / GitLab）
   - **分支**：选择要部署的分支，如 `main` 或 `master`
   - **触发方式**：可按需配置「提交代码触发」「定时触发」「手动触发」

### 3.3 添加构建任务

> **重要说明**：部署包仅包含源码和 Docker 配置，**不包含** Maven/npm 构建产物。目标主机上的 `docker compose build` 会在容器内完成后端和前端构建。因此构建阶段**无需** Java 或 Node 环境，只需执行打包脚本。

1. 点击 **添加任务** → **构建**
2. 选择 **通用构建** 或 **Shell 构建**
3. 配置如下：

**构建环境：**

- **镜像**：`ubuntu:22.04` 或 `alpine:latest`（轻量即可，需有 `bash`、`rsync`、`zip`）
- **构建命令**：

```bash
# 安装 rsync 和 zip（若镜像中无）
apt-get update && apt-get install -y rsync zip || true
# Alpine: apk add --no-cache rsync zip

# 执行项目自带的部署包构建脚本（仅打包，不执行 Maven/npm）
chmod +x ./scripts/build-deploy-package.sh
./scripts/build-deploy-package.sh

# 验证产物
DEPLOY_ZIP=$(ls DataAgent-deploy-*.zip 2>/dev/null | head -1)
if [ -z "$DEPLOY_ZIP" ]; then
  echo "ERROR: Deploy package not found"
  exit 1
fi
echo "Build artifact: $DEPLOY_ZIP"
```

**构建产物配置：**

- **产物名称**：`DataAgent-deploy`
- **产物路径**：`DataAgent-deploy-*.zip`（或填写 `*.zip`，具体以云效界面为准）
- 确保勾选「上传构建产物」

**若构建镜像无 root 权限安装软件：**

可选用已包含 `rsync`、`zip` 的镜像，如 `ubuntu:22.04`，或联系管理员预装。若无法使用 `build-deploy-package.sh`，可改用以下精简打包命令（需在项目根目录执行）：

```bash
# 手动打包（排除与 build-deploy-package.sh 相同的目录）
zip -r DataAgent-deploy-manual.zip . \
  -x "*.git*" -x "*target*" -x "*node_modules*" -x "*dist*" \
  -x "*.idea*" -x "*.vscode*" -x "docs/*" -x "*.md" -x "build-deploy-staging/*"
```

> **建议**：优先使用项目自带的 `build-deploy-package.sh`，可保证与本地打包结果一致，且排除规则完整。

### 3.4 添加部署任务（主机部署）

1. 点击 **添加任务** → **部署** → **主机部署**
2. 配置如下：

**基本配置：**

- **主机组**：选择 2.3 中创建的主机组
- **部署来源**：选择「构建产物」
- **制品**：选择上游构建任务产生的 `DataAgent-deploy-*.zip`
- **下载路径**：`/opt/dataagent/release`（可自定义）

**部署脚本：**

```bash
#!/bin/bash
set -e

RELEASE_DIR="/opt/dataagent/release"   # 与云效「下载路径」一致
COMPOSE_FILE="docker-file/docker-compose.yml"

mkdir -p $RELEASE_DIR
cd $RELEASE_DIR

# 解压部署包（云效将构建产物下载到此目录）
ZIP_FILE=$(ls DataAgent-deploy-*.zip 2>/dev/null | head -1)
if [ -n "$ZIP_FILE" ]; then
  unzip -o "$ZIP_FILE"
  cd DataAgent-deploy-*/
fi

# 确认当前在项目根目录（与 docker-file 同级）
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "ERROR: docker-compose.yml not found. Current dir: $(pwd)"
  exit 1
fi

# 使用 BuildKit 加速构建
export DOCKER_BUILDKIT=1

# 云效会注入在任务中配置的变量，如 AI_DASHSCOPE_API_KEY
# 若未配置，docker-compose.yml 中的默认值会生效（建议生产环境务必配置）

# 构建镜像（首次较慢，后续利用缓存只构建变更层；需完全重建时可加 --no-cache）
docker compose -f $COMPOSE_FILE build

# 启动服务
docker compose -f $COMPOSE_FILE up -d

# 等待服务就绪
echo "Waiting for services to start..."
sleep 15

# 健康检查（可选）
curl -sf http://localhost:8065/actuator/health 2>/dev/null && echo "Backend OK" || echo "Backend not ready"
curl -sf -o /dev/null http://localhost:3000 2>/dev/null && echo "Frontend OK" || echo "Frontend not ready"

echo "Deployment completed."
echo "  Backend:  http://<your-host>:8065"
echo "  Frontend: http://<your-host>:3000"
```

**环境变量（在任务配置中绑定）：**

- `AI_DASHSCOPE_API_KEY`：绑定到云效加密变量

> **注意**：当前 `docker-compose.yml` 中 `AI_DASHSCOPE_API_KEY` 为硬编码。若要通过云效变量注入，需在部署前生成 `docker-file/.env` 文件，或修改 `docker-compose.yml` 将 `AI_DASHSCOPE_API_KEY=sk-xxx` 改为 `AI_DASHSCOPE_API_KEY=${AI_DASHSCOPE_API_KEY:-}`。部署脚本中已 `export AI_DASHSCOPE_API_KEY`，修改后即可生效。

### 3.5 保存并运行

1. 保存流水线配置
2. 点击 **运行** 执行首次构建与部署
3. 查看构建日志和部署日志，确认无报错
4. 在浏览器访问 `http://<ECS公网IP>:3000` 验证前端，`http://<ECS公网IP>:8065` 验证后端

---

## 四、方式二：Docker 镜像 + 主机部署

此方式在流水线中构建 Docker 镜像并推送到阿里云 ACR，主机从 ACR 拉取镜像后运行。需要修改 `docker-compose.yml` 使用镜像而非 `build`。

### 4.1 修改 docker-compose 支持镜像部署

创建 `docker-file/docker-compose.prod.yml`（生产用，使用预构建镜像）：

```yaml
# 与 docker-compose.yml 结构相同，但 backend 和 frontend 使用 image 而非 build
services:
  mysql:
    # ... 保持不变 ...
  backend:
    image: registry.cn-hangzhou.aliyuncs.com/<你的命名空间>/data-agent-backend:${IMAGE_TAG:-latest}
    # 删除 build 配置
    container_name: data-agent-backend
    # ... 其余配置同 docker-compose.yml ...
  frontend:
    image: registry.cn-hangzhou.aliyuncs.com/<你的命名空间>/data-agent-frontend:${IMAGE_TAG:-latest}
    # ... 其余配置同 docker-compose.yml ...
  mysql-data:
    # ... 保持不变 ...
  postgres-data:
    # ... 保持不变 ...
# volumes、networks 同原配置
```

### 4.2 流水线配置

**构建阶段 1：构建后端镜像**

- 选择 **Docker 构建** 任务
- Dockerfile 路径：`docker-file/Dockerfile-backend`
- 镜像仓库：ACR 个人/企业实例
- 镜像标签：`${DATETIME}` 或 `latest`

**构建阶段 2：构建前端镜像**

- Dockerfile 路径：`docker-file/Dockerfile-frontend`
- 镜像仓库：同上
- 镜像标签：同上

**部署阶段：主机部署**

- 部署脚本中先 `docker login` ACR，再 `docker compose -f docker-compose.prod.yml pull && docker compose up -d`

具体步骤可参考 [云效 Docker 镜像部署到主机](https://help.aliyun.com/zh/yunxiao/user-guide/host-docker-deployment)。

---

## 五、生产环境配置建议

### 5.1 环境变量覆盖

生产环境建议通过环境变量覆盖默认配置，避免敏感信息写入镜像或仓库：

| 变量 | 说明 | 建议 |
|------|------|------|
| `AI_DASHSCOPE_API_KEY` | 大模型 API Key | 使用云效加密变量 |
| `DATA_AGENT_DATASOURCE_URL` | 若使用外部 MySQL | 指向 RDS 等 |
| `DATA_AGENT_DATASOURCE_USERNAME` | 数据库用户名 | 生产专用账号 |
| `DATA_AGENT_DATASOURCE_PASSWORD` | 数据库密码 | 强密码 + 加密存储 |
| `DATA_AGENT_DATASOURCE_SQL_INIT` | 建表初始化 | 生产建议 `never`，由 DBA 管理 |

### 5.2 使用阿里云 RDS MySQL（可选）

若希望业务库使用阿里云 RDS 而非容器内 MySQL：

1. 在 RDS 控制台创建实例，创建数据库 `nl2sql_db`
2. 导入 `schema.sql`、`data.sql`
3. 在 `docker-compose.yml` 中修改 backend 的 `DATA_AGENT_DATASOURCE_URL` 为 RDS 内网地址
4. 可移除或禁用 compose 中的 `mysql` 服务

### 5.3 反向代理与 HTTPS

生产环境建议使用 Nginx / SLB 做反向代理并配置 HTTPS：

```nginx
# 示例：Nginx 反向代理
server {
    listen 443 ssl;
    server_name your-domain.com;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    location /api/ {
        proxy_pass http://127.0.0.1:8065/;
        proxy_set_header Host $host;
        proxy_read_timeout 600s;
    }
}
```

### 5.4 数据持久化

当前 `docker-compose.yml` 已配置数据卷，`docker compose down` 不会删除数据。**切勿**使用 `docker compose down -v`，`-v` 会删除卷内数据。

---

## 六、故障排查

### 6.1 构建失败

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| Maven 依赖下载超时 | 网络问题 | 在 Dockerfile/构建脚本中配置阿里云 Maven 镜像 |
| `build-deploy-package.sh` 找不到 rsync | 构建镜像无 rsync | 使用 `apt-get install -y rsync` 或改用简化打包脚本 |
| 前端构建失败 | Node 版本或依赖问题 | 使用 Node 18+，执行 `npm ci` 确保依赖一致 |

### 6.2 部署失败

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| `docker compose` 命令不存在 | 未安装 Docker Compose v2 | 在主机上安装 `docker compose` 插件 |
| 镜像拉取超时 | 未配置镜像加速 | 配置 `/etc/docker/daemon.json` 的 `registry-mirrors` |
| 端口被占用 | 3000/8065 已被占用 | `netstat -tlnp` 检查，修改 compose 端口映射或停止冲突服务 |
| 后端启动报数据库连接失败 | MySQL 未就绪或密码错误 | 检查 `depends_on` 与 `healthcheck`，确认环境变量正确 |

### 6.3 运行时问题

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| 前端访问 502 | 后端未启动或 Nginx 代理配置错误 | 检查 backend 容器状态，查看 `docker compose logs backend` |
| 模型调用失败 | API Key 未配置或无效 | 在系统「模型配置」中填写正确的 API Key |
| Python 分析报错 | 容器内缺少 pandas/numpy | 确认 Dockerfile-backend 中已安装 pip 及依赖 |

---

## 七、部署检查清单

部署前请确认：

- [ ] ECS 已安装 Docker 和 Docker Compose
- [ ] 安全组已放行 22、3000、8065 端口
- [ ] 云效主机组已添加目标机器
- [ ] `AI_DASHSCOPE_API_KEY` 等敏感变量已配置为加密变量
- [ ] 代码已推送到云效关联的仓库
- [ ] 流水线构建产物路径与部署脚本中的解压逻辑一致

---

## 八、参考链接

- [云效 Flow 官方文档](https://help.aliyun.com/zh/yunxiao/)
- [使用流水线将 Docker 镜像部署到主机](https://help.aliyun.com/zh/yunxiao/user-guide/host-docker-deployment)
- [DataAgent 快速开始](./QUICK_START.md)
- [DataAgent 开发者指南](./DEVELOPER_GUIDE.md)

---

*文档版本：1.0 | 更新日期：2025-02*
