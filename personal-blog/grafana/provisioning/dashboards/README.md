# Grafana 仪表盘 JSON 文件存放目录

## 说明

将仪表盘 JSON 文件放在此目录，Grafana 启动时自动导入（每 30 秒热重载）。

**重要**：JSON 中的 `datasource.uid` 必须为 `prometheus`，与 `datasources/prometheus.yml` 中的 UID 一致。

---

## 导出步骤（从 Grafana Cloud）

1. 打开 Grafana Cloud → 找到要导出的仪表盘
2. 右上角 **⚙ Dashboard Settings** → **JSON Model**
3. 点击 **Copy to Clipboard**
4. 粘贴保存为 `.json` 文件放在此目录

或者从 Grafana 官方社区下载：
- SpringBoot APM：https://grafana.com/grafana/dashboards/12900
- MySQL：https://grafana.com/grafana/dashboards/14057
- Redis：https://grafana.com/grafana/dashboards/763
- Caddy：https://grafana.com/grafana/dashboards/14280

---

## 文件命名规范

```
dashboards/
├── dashboards.yml          # Provider 配置（已生成，不要修改）
├── README.md               # 本文件
├── springboot-apm.json     # Spring Boot APM 仪表盘
├── mysql.json              # MySQL 监控仪表盘
├── redis.json              # Redis 监控仪表盘
└── caddy.json              # Caddy 网关仪表盘
```

## 修改 datasource UID

下载的社区仪表盘可能使用不同的 datasource UID，需要替换为 `prometheus`：

```bash
# 批量替换 datasource uid（在 dashboards 目录下执行）
sed -i 's/"uid": ".*"/"uid": "prometheus"/g' *.json
```
