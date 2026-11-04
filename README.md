# 航迹 WingTrace · 部署包（Docker）

一个自包含的单文件网页 + 一套现成的容器与 Nginx 配置。**本站是纯前端静态站点：没有后端、没有数据库、页面不发起任何外部请求**，所以「部署」就是把这一个 HTML 交给一个静态服务器。

## 包里有什么

| 文件 | 作用 |
| :--- | :--- |
| `index.html` | 站点本体（单文件，图片与图标全部内联，可直接双击打开） |
| `Dockerfile` | 基于 `nginx:1.27-alpine` 的静态托管镜像（基础镜像用 `NGINX_IMAGE` 构建参数可覆盖） |
| `nginx.conf` | 站点级 Nginx 配置：静态托管 + gzip + 基础安全响应头 |
| `docker-compose.yml` | 一条命令起站点，端口 `8080 → 80` |
| `nginx.https.conf.example` | 以后配域名和 HTTPS 时用的配置示例（现在不用管） |
| `.dockerignore` | 构建上下文精简 |
| `README.md` | 本文件 |

## 前置条件

- **Windows / macOS**：装好 Docker Desktop 并**先启动它**（托盘图标变绿）。
- **Linux 服务器**：装好 `docker` 与 `docker compose` 插件。

> 自查：`docker info` 能正常输出服务端版本，说明守护进程已就绪。如果报 `failed to connect to the docker API at npipe:...` 或 `Cannot connect to the Docker daemon`，就是 Docker Desktop 还没启动。

## 本地跑起来

在本包目录下执行：

```bash
docker compose up -d --build
```

然后浏览器打开 **http://localhost:8080** 即可看到站点。

不想用 compose 也行：

```bash
docker build -t wingtrace-flyer-community:1.0.0 .
docker run -d --name wingtrace -p 8080:80 --restart unless-stopped wingtrace-flyer-community:1.0.0
```

## 验证部署是否正常

```bash
docker compose ps                       # 容器应为 running（本包不内置容器内健康检查，见下方说明）
curl -I http://localhost:8080           # 期望 HTTP/1.1 200 OK 且 Content-Type: text/html
docker compose logs -f wingtrace        # 看访问日志，Ctrl+C 退出
```

页面里可以顺手验证几处：顶部导航的「登录 / 注册」能展开账号面板；手机号填 11 位后点「获取验证码」会提示演示验证码；晒图广场选「航展」会显示空状态。

## 常用运维

```bash
docker compose stop        # 停止
docker compose start       # 再启动
docker compose restart     # 重启
docker compose logs -f     # 看日志
docker compose down        # 停止并删除容器（镜像还在）
docker compose up -d --build   # 改了 index.html 后重建生效
```

## 改端口

只改 `docker-compose.yml` 里 `ports` 的左边那个数字，比如换成 `80:80` 就是直接用 80 端口：

```yaml
    ports:
      - "80:80"
```

## 关于站点本身的两点说明

1. **内容为演示数据**：站内的动态、评论、航线、问答与统计都是示例内容，配图是 AI 生成的概念示意图，页脚已声明。
2. **注册登录是前端演示**：手机号/邮箱表单、校验、验证码提示、登录态都真实可交互，但全部保存在浏览器内存里（刷新即重置），**不发送短信或邮件、不连接任何服务器、不保存任何凭据**。要变成真实可用的账号体系，需要另外接后端（见下）。

## 后续上云：腾讯云 CVM / 轻量应用服务器

这套 Docker 配置原样就能上云，推荐顺序：

1. **基础镜像**：服务器能访问 Docker Hub 或其镜像源即可；若服务器也已缓存过某个 nginx 镜像，用 `NGINX_IMAGE=<镜像名> docker compose up -d --build` 直接复用。
2. **装 Docker**：登录服务器（OrcaTerm / SSH），按官方脚本安装 Docker 与 compose 插件；国内机器若拉取镜像慢，可配置镜像加速器。
2. **上传本包**：用 `scp`、腾讯云 OrcaTerm 的文件上传或宝塔面板，把整个目录传到服务器，例如 `/opt/wingtrace-deploy`。
3. **起容器**：
   ```bash
   cd /opt/wingtrace-deploy
   docker compose up -d --build
   ```
4. **放行端口**：在轻量应用服务器/云服务器的**防火墙/安全组**里放行 `80`（和以后的 `443`）。临时体验也可以只放行 `8080`，直接用 `http://服务器公网IP:8080` 访问。
5. **绑域名**：在域名解析里加一条 A 记录指向服务器公网 IP；把 `nginx.https.conf.example` 里的 `server_name` 换成你的域名。
6. **配 HTTPS**：在腾讯云申请免费 SSL 证书（下载 Nginx 版），把证书放到服务器并把 `nginx.https.conf.example` 的内容合并进站点配置，然后 `docker compose restart`；或者用 certbot 自动签发续期。
7. **备案提醒**：服务器在中国大陆且用域名对外提供服务，需要先完成 **ICP 备案**，否则域名访问会被拦截（先用 IP 加端口的方式不受此限）。
8. **升级为真实社区**（可选）：真实的注册登录、图片上传、评论落库都需要后端服务与数据库，届时把本包里的静态站点换成前端构建产物、再由 Nginx 反向代理到后端即可；现在的 `nginx.conf` 已经预留了清晰的替换位置。

## 排错

| 现象 | 处理 |
| :--- | :--- |
| `failed to connect to the docker API` / `Cannot connect to the Docker daemon` | Docker Desktop 没启动，先启动它；Linux 上执行 `sudo systemctl start docker` |
| `port is already allocated` / 端口被占用 | 改 `docker-compose.yml` 里端口左边的数字，或先停掉占用该端口的程序 |
| 页面样式或脚本不生效 | 若你在前面又挂了反向代理/CDN，确认它没有覆盖或收紧 `Content-Security-Policy`；页面需要允许内联样式与脚本 |
| 改了 `index.html` 但页面没变 | 执行 `docker compose up -d --build` 重建；浏览器强制刷新（Ctrl+F5） |
| 容器起来但访问 502/无法连接 | `docker compose ps` 看状态、`docker compose logs` 看日志；确认端口映射与安全组一致 |