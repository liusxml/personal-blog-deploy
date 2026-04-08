# personal-blog-deploy

个人博客的完整生产部署配置，基于 Docker Compose 实现一键部署，涵盖应用服务、网关、可观测性全栈。

---

## 目录结构

```
personal-blog-deploy/
├── dockge-compose.yml          # Dockge 容器管理面板（独立部署）
├── .env.example                # Dockge 根目录环境变量模板
│
├── personal-blog/              # 博客主栈（核心部署目录）
│   ├── compose.yml             # 主 Compose 文件（所有服务定义）
│   ├── .env.example            # 博客主栈环境变量模板
│   │
│   ├── caddy/                  # Caddy 反向代理配置
│   │   ├── Caddyfile           # 多子域名路由规则
│   │   └── certs/              # Cloudflare Origin CA 证书（15 年长效证书）
│   │
│   ├── mysql/                  # MySQL 配置
│   │   ├── custom.cnf          # 自定义配置（字符集、InnoDB 调优等）
│   │   ├── exporter.cnf.example # mysqld_exporter 连接配置模板
│   │   └── init/               # 初始化 SQL 脚本（首次启动按字母顺序执行）
│   │       ├── V0.0.1__create_database.sql
│   │       ├── V1.0.0__init_schema.sql
│   │       └── ...（共 13 个迁移脚本）
│   │
│   ├── redis/                  # Redis 配置
│   │   └── redis.conf          # AOF+RDB 持久化、内存限制等
│   │
│   ├── alloy/                  # Grafana Alloy 配置
│   │   └── config.alloy        # 日志→Loki / 指标→Mimir / Traces→Tempo
│   │
│   ├── prometheus/             # Prometheus 配置
│   │   └── prometheus.yml      # Scrape jobs（backend、caddy、redis、mysql）
│   │
│   ├── grafana/                # Grafana Provisioning
│   │   └── provisioning/       # 数据源与仪表盘自动配置
│   │
│   ├── dozzle/                 # Dozzle 容器日志查看器配置
│   │   └── users.yml           # 登录用户（需在服务器上手动生成）
│   │
│   ├── cv/                     # CV 简历静态文件
│   ├── logs/                   # 本地日志目录（已废弃，保留目录结构）
│   └── ssh/                    # Ops Agent SSH 私钥（.gitignore 中，不提交）
│
└── samples/                    # 单服务独立部署示例（参考用）
    ├── compose-infra.yml
    ├── compose.backend.yml
    ├── compose.backup.yml
    ├── compose.caddy.yml
    ├── compose.dozzle.yml
    ├── compose.mysql.yml
    └── compose.redis.yml
```

---

## 服务架构

```
Internet
    │
    ▼
┌──────────────────────────┐
│  Caddy (80/443/443 UDP)  │  HTTP/3 · 自动 HTTPS · 反向代理
└────────────┬─────────────┘
             │  app-net (bridge)
    ┌────────┼────────────────────────────────┐
    │        │                                │
    ▼        ▼                                ▼
frontend  admin  monitor(按需)          api.chonkybird.com
(3000)   (3000)   (9000)                     │
                                             ▼
                                         backend (8080)
                                        Spring Boot 3.5
                                         │         │
                                    mysql:3306  redis:6379
                                    (9.6.0)    (7.4-alpine)

── 可观测性 ─────────────────────────────────────────────────────
Prometheus → [backend, caddy, redis-exporter, mysql-exporter]
Grafana    → Prometheus（本地可视化）
Alloy      → Grafana Cloud（Loki / Mimir / Tempo）
Dozzle     → 实时容器日志（dozzle.chonkybird.com）
Dockge     → 容器管理面板（dockge.chonkybird.com，宿主机网桥访问）
```

### 子域名路由一览

| 子域名 | 目标服务 | 说明 |
|:---|:---|:---|
| `chonkybird.com` / `www` | `frontend:3000` | 博客前台（Next.js） |
| `admin.chonkybird.com` | `admin:3000` | 管理后台（Next.js） |
| `api.chonkybird.com` | `backend:8080` | REST API（Spring Boot） |
| `monitor.chonkybird.com` | `monitor:9000` | Spring Boot Admin（按需启动） |
| `grafana.chonkybird.com` | `grafana:3000` | 监控可视化（Grafana OSS） |
| `dozzle.chonkybird.com` | `dozzle:8080` | 实时容器日志 |
| `dockge.chonkybird.com` | `172.17.0.1:5001` | 容器管理（Dockge，宿主机网桥） |
| `cv.chonkybird.com` | `/srv/cv` | 简历静态页面 |

---

## 快速开始

### 前置条件

- VPS 已安装 Docker Engine（推荐 27.x）
- 域名已解析到服务器 IP，并启用 Cloudflare 代理
- Cloudflare Origin CA 证书已下载，放置于 `personal-blog/caddy/certs/`

### 1. 克隆仓库

```bash
git clone <repo-url> /opt/personal-blog-deploy
cd /opt/personal-blog-deploy
```

### 2. 配置环境变量

```bash
cd personal-blog
cp .env.example .env
vim .env   # 填写所有 required 字段（见下方环境变量说明）
```

### 3. 生成 MySQL Exporter 配置

```bash
# 参考 mysql/exporter.cnf.example 创建 exporter.cnf
cp mysql/exporter.cnf.example mysql/exporter.cnf
vim mysql/exporter.cnf   # 填写 MYSQL_EXPORTER_PASSWORD
```

### 4. 生成 Dozzle 用户文件

```bash
# 需要先安装 dozzle CLI 或使用 Docker 运行
docker run --rm amir20/dozzle:latest generate admin --password <your-password> > dozzle/users.yml
```

### 5. 生成 Ops Agent SSH 密钥

```bash
# 在 personal-blog/ 目录下执行
ssh-keygen -t ed25519 -f ./ssh/id_ed25519 -N '' -C 'blog-ops-agent'
# 将公钥追加到 VPS 的 blog-ops 用户授权列表
cat ./ssh/id_ed25519.pub >> /home/blog-ops/.ssh/authorized_keys
```

> ⚠️ `ssh/` 目录已加入 `.gitignore`，私钥不会被提交。

### 6. 启动所有服务

```bash
docker compose up -d
```

### 7. 验证服务状态

```bash
docker compose ps
docker compose logs backend -n 50 -f
```

---

## 环境变量说明

完整变量定义见 [`personal-blog/.env.example`](personal-blog/.env.example)。

### 必填项

| 变量 | 说明 | 生成命令 |
|:---|:---|:---|
| `MYSQL_ROOT_PASSWORD` | MySQL root 密码 | `openssl rand -base64 32` |
| `MYSQL_PASSWORD` | 应用数据库账号密码 | `openssl rand -base64 32` |
| `MYSQL_EXPORTER_PASSWORD` | mysqld_exporter 专用低权限账号密码 | `openssl rand -base64 32` |
| `REDIS_PASSWORD` | Redis 认证密码 | `openssl rand -base64 32` |
| `JWT_SECRET` | JWT 签名密钥（≥256 bit） | `openssl rand -hex 64` |
| `BITIFUL_ENDPOINT` | Bitiful OSS 接入点 | — |
| `BITIFUL_ACCESS_KEY` | Bitiful Access Key | — |
| `BITIFUL_SECRET_KEY` | Bitiful Secret Key | — |
| `GRAFANA_CLOUD_API_KEY` | Grafana Cloud Service Account Token | Grafana Cloud 控制台 |
| `GRAFANA_LOKI_URL` | Loki 推送地址 | Grafana Cloud 控制台 |
| `GRAFANA_LOKI_USERNAME` | Loki 用户名 | Grafana Cloud 控制台 |
| `GRAFANA_PROMETHEUS_URL` | Prometheus 推送地址 | Grafana Cloud 控制台 |
| `GRAFANA_PROMETHEUS_USERNAME` | Prometheus 用户名 | Grafana Cloud 控制台 |
| `GRAFANA_TEMPO_URL` | Tempo 推送地址 | Grafana Cloud 控制台 |
| `GRAFANA_TEMPO_USERNAME` | Tempo 用户名 | Grafana Cloud 控制台 |
| `DASHSCOPE_API_KEY` | 阿里云通义千问 API Key | DashScope 控制台 |
| `QDRANT_API_KEY` | Qdrant Cloud API Key | cloud.qdrant.io |
| `ADMIN_SERVER_PASSWORD` | Spring Boot Admin 登录密码 | `openssl rand -base64 32` |
| `OPS_WEBHOOK_SECRET` | GitHub Webhook HMAC 密钥 | `openssl rand -base64 32` |

### 可选项（有默认值）

| 变量 | 默认值 | 说明 |
|:---|:---|:---|
| `MYSQL_DATABASE` | `blog_db` | 数据库名 |
| `MYSQL_USER` | `blog` | 应用数据库账号 |
| `BITIFUL_BUCKET` | `blog-module-file` | OSS Bucket 名称 |
| `BITIFUL_REGION` | `cn-east-1` | OSS 区域 |

---

## 常用操作

### 服务管理

```bash
# 启动所有服务（后台）
docker compose up -d

# 重启单个服务
docker compose restart backend

# 查看服务状态
docker compose ps

# 查看实时日志
docker compose logs <service> -n=100 -f

# 停止所有服务（保留数据）
docker compose down

# 停止并清除所有数据（⚠️ 不可恢复）
docker compose down -v
```

### 按需启动 Spring Boot Admin

`monitor` 服务默认不随主栈启动，需要时单独执行：

```bash
docker compose --profile monitor up -d monitor
```

### Caddy 热重载（不停机更新配置）

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### 拉取最新镜像并滚动更新

```bash
docker compose pull
docker compose up -d
```

---

## Dockge 部署（容器管理面板）

Dockge 独立于主栈单独部署，使用 `dockge-compose.yml`：

```bash
cd /opt/personal-blog-deploy
docker compose -f dockge-compose.yml up -d
```

> Dockge 监听在 `172.17.0.1:5001`，通过 Caddy 以 `dockge.chonkybird.com` 对外暴露，公网无法直连。

---

## 可观测性说明

### 指标采集（Prometheus）

Prometheus 本地抓取以下目标（15s 间隔），数据保留 15 天：

| Job | 目标 | 说明 |
|:---|:---|:---|
| `personal-blog-backend` | `backend:8080/actuator/prometheus` | Spring Boot Actuator 指标 |
| `caddy` | `caddy:2019/metrics` | Caddy 内置指标（HTTP 请求、连接等） |
| `redis` | `redis-exporter:9121` | Redis 运行状态 |
| `mysql` | `mysql-exporter:9104` | MySQL 运行状态 |

### 日志采集（Grafana Alloy）

Alloy 通过 Docker socket 采集所有容器的 stdout 日志，推送到 Grafana Cloud Loki。

### 链路追踪（OpenTelemetry）

Backend 通过 `opentelemetry-javaagent.jar`（无侵入）将 Traces 推送到 Alloy（`http://alloy:4318`），再由 Alloy 转发到 Grafana Cloud Tempo。

### 访问 Grafana

```
https://grafana.chonkybird.com
```

匿名访客以 Viewer 角色访问（只读），支持 iframe 嵌入。

---

## TLS 配置说明

本站使用 **Cloudflare Origin CA 15 年长效证书**，而非 Let's Encrypt：

- Cloudflare 边缘（访客 ↔ Cloudflare）：由 Universal SSL 自动管理
- Cloudflare 到源服务器（Cloudflare ↔ Caddy）：使用 Origin CA 证书

证书文件放置于：

```
personal-blog/caddy/certs/
├── chonkybird.com.pem   # 证书（含中间链）
└── chonkybird.com.key   # 私钥（.gitignore 中，不提交）
```

---

## 安全说明

| 措施 | 说明 |
|:---|:---|
| MySQL / Redis | 仅绑定 `127.0.0.1`，不可从公网直接访问；可通过 SSH 隧道使用 DataGrip 连接 |
| Dozzle | 通过 Caddy 子域名 + 用户名密码保护，不直接暴露端口 |
| Dockge | 监听 `172.17.0.1`（Docker 网桥），仅 Caddy 反代访问，公网不可达 |
| Alloy Admin UI | 仅绑定 `127.0.0.1:12345`，通过 SSH 隧道访问 |
| SSH 私钥 | 存放于 `ssh/` 目录，`.gitignore` 排除，不提交 Git |
| 敏感配置 | `.env` 不提交 Git；`certs/*.key` 不提交 Git |

---

## 技术栈版本

| 服务 | 镜像 | 版本 |
|:---|:---|:---|
| 博客后端 | `liusxml/personal-blog-backend` | latest（GitHub Actions 自动构建） |
| 博客前台 | `liusxml/personal-blog-frontend` | latest |
| 管理后台 | `liusxml/personal-blog-admin` | latest |
| Spring Boot Admin | `liusxml/personal-blog-admin-server` | latest |
| MySQL | `mysql` | 9.6.0 |
| Redis | `redis` | 7.4-alpine |
| Caddy | `caddy` | 2.11.1-alpine |
| Prometheus | `prom/prometheus` | v3.11.0 |
| Grafana | `grafana/grafana-oss` | 12.4.2 |
| Alloy | `grafana/alloy` | v1.15.0 |
| redis_exporter | `oliver006/redis_exporter` | v1.67.0-alpine |
| mysqld_exporter | `prom/mysqld-exporter` | v0.16.0 |
| Dozzle | `amir20/dozzle` | v10.2.1 |
| Dockge | `louislam/dockge` | 1 |
