# 航迹 WingTrace —— 静态单文件站点，Nginx 托管

# 基础镜像可用 --build-arg NGINX_IMAGE=<镜像源>/library/nginx:<tag> 覆盖，
# 便于在镜像源受限、或本机已缓存某个 nginx 镜像的环境下直接使用。
ARG NGINX_IMAGE=nginx:1.27-alpine
FROM ${NGINX_IMAGE}

LABEL org.opencontainers.image.title="wingtrace-flyer-community" \
      org.opencontainers.image.description="飞友社区单文件静态站点（Nginx 托管）" \
      org.opencontainers.image.version="1.0.0"

# 站点：单个自包含 HTML，所有图片与图标已内联，页面不发起任何外部请求
COPY index.html /usr/share/nginx/html/index.html

# 站点级 Nginx 配置（静态托管 + gzip + 基础安全响应头）
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# 关于健康检查：这里不内置 HEALTHCHECK。
# 不同 nginx 基础镜像自带的探测工具不一致（alpine 有 wget 无 curl，Debian 有 curl 无 wget），
# 内置会让另一种镜像被误判为 unhealthy。请在宿主机侧验证：
#   docker compose ps                # 期望 running
#   curl -I http://localhost:8080    # 期望 200 且 Content-Type: text/html
#
# 若你固定使用 alpine 镜像并想启用容器内健康检查，可自行追加这一行：
#   HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1/index.html || exit 1