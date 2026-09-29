# DentStudy 阿里云 ECS 部署

这套配置适用于单台 ECS：前端由 Nginx 提供，后端 API 运行在 Docker 内部网络，前端通过同域名 `/api` 访问后端。初次部署不需要单独购买 API 域名。

## 服务器准备

在 Alibaba Cloud Linux 3 ECS 上执行：

```bash
sudo dnf update -y
sudo dnf install -y git docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

重新登录 SSH 后执行：

```bash
git clone git@github.com:stein-wang0226/dentstudy-mvp.git
cd dentstudy-mvp
mkdir -p data
docker compose -f deploy/docker-compose.aliyun.yml up -d --build
```

构建 Flutter Web 镜像需要一定内存。2 GiB ECS 可以运行服务，但如果构建过程中内存不足，可先创建 2 GiB Swap，或临时升级到 4 GiB 完成构建。

## 检查

```bash
curl http://127.0.0.1/health
curl http://127.0.0.1/api/health
curl http://127.0.0.1/api/v1/questions
```

浏览器打开 `http://ECS公网IP`，应能看到 DentStudy。数据库文件位于 `data/dentstudy.sqlite3`，不要删除 `data` 目录。

## 域名和 HTTPS

将域名 A 记录解析到 ECS 公网 IP。中国大陆 ECS 对外使用域名需要完成 ICP 备案。备案完成后，可使用 Nginx 或阿里云 SSL 证书配置 HTTPS；HTTPS 启用后，前端的同源 `/api` 配置无需改动。

## 更新代码

```bash
cd dentstudy-mvp
git pull --ff-only origin main
docker compose -f deploy/docker-compose.aliyun.yml up -d --build
```
