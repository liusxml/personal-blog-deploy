-- =============================================================================
-- MySQL Exporter 低权限用户初始化脚本
-- 此用户仅供 prom/mysqld-exporter 采集监控指标使用，遵循最小权限原则
-- 参考：https://github.com/prometheus/mysqld_exporter#required-grants
-- =============================================================================
-- ⚠️ 注意：此脚本在 MySQL 数据目录已存在时不会重新执行（Docker Compose 官方行为）
-- 若 MySQL 已初始化，需手动执行：
--   docker compose exec mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} < mysql/init/02-exporter-user.sql

-- 使用 SET 从 MySQL 环境变量获取密码（Docker 通过 MYSQL_EXPORTER_PASSWORD 传入）
-- 注意：MySQL init 脚本在 docker-entrypoint.sh 中以 root 身份执行，可直接使用 MYSQL_ROOT_PASSWORD 连接
-- 由于 Docker Compose 初始化脚本不支持 shell 变量展开，密码需通过环境变量占位符由 Docker 处理
-- 此处使用 '${MYSQL_EXPORTER_PASSWORD}' 作为占位，实际部署时需替换或通过外部工具注入

CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY '${MYSQL_EXPORTER_PASSWORD}';

-- mysqld_exporter 最小权限集（v0.16.0）
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

FLUSH PRIVILEGES;
