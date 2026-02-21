#!/usr/bin/env bash
#Copyright 2024-2026 the original author or authors.
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.
#
# 构建仅含部署所需文件的发布包，便于在其他环境用 docker-compose 部署。
# 排除：target、node_modules、前端构建产物、文档、CI、IDE 等。
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# 从根 pom 读取版本（简单提取 revision）
VERSION=$(sed -n 's/.*<revision>\([^<]*\)<\/revision>.*/\1/p' pom.xml | head -1)
[ -z "$VERSION" ] && VERSION="1.0.0-SNAPSHOT"

OUTPUT_NAME="DataAgent-deploy-${VERSION}"
STAGING="${ROOT_DIR}/build-deploy-staging/${OUTPUT_NAME}"
ARCHIVE="${ROOT_DIR}/${OUTPUT_NAME}.zip"

echo "Building deploy package: ${OUTPUT_NAME}.zip (version ${VERSION})"

# 清理并创建临时目录
rm -rf "$(dirname "$STAGING")"
mkdir -p "$STAGING"

# 使用 rsync 复制，排除对部署无用的内容
rsync -a \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='target' \
  --exclude='**/target' \
  --exclude='**/node_modules' \
  --exclude='**/dist' \
  --exclude='**/.vuepress/dist' \
  --exclude='.idea' \
  --exclude='.vscode' \
  --exclude='*.iml' \
  --exclude='.DS_Store' \
  --exclude='docs' \
  --exclude='img' \
  --exclude='*.md' \
  --exclude='CI' \
  --exclude='*.log' \
  --exclude='.cache' \
  --exclude='.env' \
  --exclude='.dockerignore' \
  --exclude='.cursorindexingignore' \
  --exclude='.specstory' \
  --exclude='uploads' \
  --exclude='.java-version' \
  --exclude='build-deploy-staging' \
  --exclude='DataAgent-deploy-*.zip' \
  . "$STAGING/"

# 再次删除可能被部分 rsync 版本带入的目录（在 staging 内用相对路径删除更可靠）
(cd "$STAGING" && rm -rf target data-agent-management/target data-agent-frontend/node_modules data-agent-frontend/dist)

# 若存在 docker-file，确保 DEPLOY.md 存在（上面 --exclude 对 ! 可能无效，这里直接写文件）
DEPLOY_MD="$STAGING/docker-file/DEPLOY.md"
mkdir -p "$(dirname "$DEPLOY_MD")"
cat > "$DEPLOY_MD" << 'DEPLOY_EOF'
# 部署说明

本目录为 DataAgent 的 Docker 部署配置，与上层目录中的后端、前端源码一起，用于在任意环境下通过 Docker Compose 一键部署。

## 环境要求

- Docker
- Docker Compose（v2）

## 国内网络加速（可选）

若拉取 Docker Hub 基础镜像较慢，可配置阿里云镜像加速：
1. 编辑 `/etc/docker/daemon.json`，添加 `"registry-mirrors": ["https://registry.cn-hangzhou.aliyuncs.com"]`
2. 或登录 [阿里云容器镜像服务](https://cr.console.aliyun.com/) 获取个人专属加速地址
3. 执行 `systemctl restart docker` 生效

项目内 Maven/npm/pip/apt 已使用阿里云或国内镜像源，无需额外配置。

## 部署步骤

在**本仓库根目录**（与 `docker-file` 同级）执行：

```bash
export DOCKER_BUILDKIT=1
docker compose -f docker-file/docker-compose.yml build
docker compose -f docker-file/docker-compose.yml up -d
```

- 后端：http://localhost:8065
- 前端：http://localhost:3000
- MySQL（业务库）：容器内 3306，未映射宿主机端口

## 仅重建并启动后端/前端（保留数据库数据）

```bash
docker compose -f docker-file/docker-compose.yml up -d --build backend frontend
```

注意：不要使用 `docker compose down -v`，`-v` 会删除数据卷。
DEPLOY_EOF

# 打 zip 包（-x 排除 target/node_modules/dist，确保包内不含）
cd "$(dirname "$STAGING")"
zip -rq "$ARCHIVE" "$OUTPUT_NAME" \
  -x "*target*" \
  -x "*node_modules*" \
  -x "*data-agent-frontend/dist*"
cd "$ROOT_DIR"
rm -rf "$(dirname "$STAGING")"

echo "Done: $(realpath "$ARCHIVE")"
