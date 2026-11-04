#!/usr/bin/env bash
# 航迹 WingTrace —— 腾讯云轻量应用服务器 / CVM 一键部署脚本
# 站点形态：单文件自包含 HTML，无后端、无数据库、页面不发起任何外部请求。
# 线上安全头（含 Content-Security-Policy）由部署包内 nginx.conf 原样下发。
#
# 用法（在服务器上执行，需 root 或 sudo）：
#   sudo bash deploy.sh                        # 部署包已上传到 /opt/wingtrace-deploy
#   sudo bash deploy.sh /path/to/deploy       # 自定义部署包目录
#   sudo bash deploy.sh --git <仓库地址>       # 从 GitHub 仓库 clone 后部署
#   PORT=80 sudo bash deploy.sh               # 改对外端口（默认 8080）
#
# 注意：本脚本只操作服务器上的部署副本，不修改本地源文件与页面产物。

set -euo pipefail

EXPECTED_SHA="10771fe6729c4583270c4d82d94eb44fdcbb268ba7a1d06d4f8cf98bdcf7945a"
PORT="${PORT:-8080}"
APP_DIR="/opt/wingtrace-deploy"
SRC_DIR=""

log() { printf '\n[航迹] %s\n' "$*"; }

# 1. 定位部署包
if [ "${1:-}" = "--git" ]; then
  REPO="${2:-}"
  [ -n "$REPO" ] || { echo "用法：sudo bash deploy.sh --git <仓库地址>"; exit 1; }
  command -v git >/dev/null 2>&1 || { echo "缺少 git，请先安装：apt-get update && apt-get install -y git"; exit 1; }
  if [ -d "$APP_DIR/.git" ]; then
    log "已有仓库，拉取最新内容"
    git -C "$APP_DIR" pull --rebase
  else
    log "克隆部署包"
    git clone "$REPO" "$APP_DIR"
  fi
  SRC_DIR="$APP_DIR"
elif [ -n "${1:-}" ]; then
  SRC_DIR="$1"
else
  SRC_DIR="$APP_DIR"
fi

[ -f "$SRC_DIR/index.html" ] || { echo "找不到 $SRC_DIR/index.html，请确认部署包已上传"; exit 1; }
[ -f "$SRC_DIR/docker-compose.yml" ] || { echo "找不到 $SRC_DIR/docker-compose.yml"; exit 1; }
[ -f "$SRC_DIR/nginx.conf" ] || { echo "找不到 $SRC_DIR/nginx.conf，CSP 响应头将无法下发"; exit 1; }

# 2. 产物校验：确保上传的是本地已验证过的那一版
ACTUAL_SHA="$(sha256sum "$SRC_DIR/index.html" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "index.html 校验值与已验证产物不一致："
  echo "  期望 $EXPECTED_SHA"
  echo "  实际 $ACTUAL_SHA"
  echo "若确为重新生成的新版产物，请先核对 build_site.py 输出，再更新本脚本的 EXPECTED_SHA。"
  exit 1
fi
log "产物校验通过（1,309,253 字节，与本地已验证版本一致）"

# 3. Docker 环境检查（自动适配「用户已在 docker 组」与「需要 sudo」两种情形）
command -v docker >/dev/null 2>&1 || { echo "缺少 Docker。轻量服务器建议直接选用预装 Docker 的系统镜像。"; exit 1; }
if docker info >/dev/null 2>&1; then
  DC="docker compose"
elif sudo -n docker info >/dev/null 2>&1; then
  DC="sudo docker compose"
else
  echo "Docker 守护进程不可访问。请确认服务已启动（sudo systemctl start docker），或执行 sudo usermod -aG docker \$USER 后重新登录。"; exit 1
fi
$DC version >/dev/null 2>&1 || { echo "缺少 docker compose 插件，请安装 docker-compose-plugin。"; exit 1; }

# 4. 端口（只改服务器副本里的端口映射，不动页面与 nginx 配置）
if [ "$PORT" != "8080" ]; then
  sed -i -E "s|^([[:space:]]*)- \"[0-9]+:80\"|\1- \"${PORT}:80\"|" "$SRC_DIR/docker-compose.yml"
  log "对外端口已设为 ${PORT}"
fi

# 5. 构建并启动
cd "$SRC_DIR"
log "构建并启动容器"
# 如基础镜像拉取受限，可先设置镜像源再重跑，例如：
#   NGINX_IMAGE=docker.m.daocloud.io/library/nginx:1.27-alpine sudo -E bash deploy.sh
$DC up -d --build

# 6. 验证 HTTP 状态与安全响应头
for _ in 1 2 3 4 5; do
  STATUS="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" || true)"
  [ "$STATUS" = "200" ] && break
  sleep 1
done
log "验证结果"
curl -sI "http://127.0.0.1:${PORT}/" | grep -iE '^(HTTP/|Content-Type:|Content-Security-Policy:|X-Content-Type-Options:|X-Frame-Options:|Referrer-Policy:)' || true
echo "HTTP 状态码：$STATUS"

CSP="$(curl -sI "http://127.0.0.1:${PORT}/" | grep -i '^Content-Security-Policy:' || true)"
[ "$STATUS" = "200" ] || { echo "站点未返回 200，请查看：$DC logs -f"; exit 1; }
[ -n "$CSP" ] || { echo "未检测到 CSP 响应头，请检查 nginx.conf 是否被正确 COPY 进镜像。"; exit 1; }

log "部署完成"
echo "本机访问：http://127.0.0.1:${PORT}/"
echo "公网访问：http://<服务器公网IP>:${PORT}/   （需在腾讯云防火墙 / 安全组放行 ${PORT}）"
echo "常用运维：$DC ps | logs -f | restart | down | up -d --build"
echo "域名与 HTTPS：参见部署包内 nginx.https.conf.example；大陆地域用域名对外服务需先完成 ICP 备案。"
