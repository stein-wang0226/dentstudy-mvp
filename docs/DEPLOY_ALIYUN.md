# DentStudy 阿里云 ECS 部署

## 当前线上部署（2026-10-14）

实际服务器使用宿主机 Nginx + `dentstudy.service`，不是下面的 Docker 方案。
正式入口为 `https://dentstudy.uno`，HTTP 自动跳转 HTTPS。`www` DNS 仍暂停。

- 客户端版本：`0.2.6`（章节连续浏览、关键词搜索、本地字库、错题分层、学习巩固、知识点笔记、静态渐变欢迎页与联系作者入口）；后端仍为 `5b00b84`，综合题库 3520 道，原有 ID 全部保留。
- 后端：`/opt/dentstudy-current` 指向 `/opt/dentstudy-releases/5b00b84`。
- 前端：`/var/www/dentstudy-current` 指向 `/var/www/dentstudy-releases/20261014-learning-v025`。
- 数据库：`/var/lib/dentstudy/dentstudy.sqlite3`，更新程序不能替换此文件。
- 旧代码 `/opt/dentstudy`、旧网页 `/var/www/dentstudy` 均保留。
- 更新前的数据库与配置备份：`/opt/backups/dentstudy-20261013`，数据库已验证完整性。
- HTTPS 使用 Let's Encrypt，`dentstudy-certbot.timer` 每天检查两次续期，续期成功后检查并重载 Nginx。
- `/.well-known/acme-challenge/` 继续使用 `/var/www/dentstudy`，不要随发布删除此目录。

配置模板：`deploy/nginx.ecs-https.conf`、`deploy/dentstudy-ecs-override.conf`、
`deploy/dentstudy-certbot.service` 和 `deploy/dentstudy-certbot.timer`。
构建 Web 时使用 `--no-web-resources-cdn --dart-define=API_URL=/api`
及 `--dart-define=QUESTION_BANK_ASSET=assets/all_questions.json`。
发布时同时传入 `--dart-define=APP_VERSION=0.2.6` 和
`--dart-define=BUILD_TIME=实际北京时间`，在“我的”显示版本与更新时间。
当前 GitHub workflow 只做检查，不会自动部署；代码推送后仍需单独构建和上传。

0.2.6 的验收路径：顶部右侧 → 联系作者 → 邮箱或微信二维码；
今日 → 今日计划右上方切换学习方向；
进入网站 → 静态渐变 Logo → 开始学习或登录／注册；
题本 → 错题优先级或笔记；
题库 → 查看章节掌握状态；任一练习解析 → 学习巩固 → 同考点题解析；
学情 → 下一步复盘。
仍保留 0.2.0 的验收路径：题库 → 搜索题目关键词（试“咬合力”或“𬌗力”）；
题库 → 学科 → 章节 → 任意题 → 下一题 → 章末下一章；
解析右上“题目目录”跳题；返回后章节显示“继续解析”；我的底部核对版本。
阅读进度键为 `reading:账号ID:考试方向:学科:章节`，仅保存在本机，
不影响作答记录、不进入事件同步。搜索支持题干、共用题干、选项、解析、
考点、标签和题目编号；多关键词为同时匹配，结果优先显示题干匹配。
字体精简生成方法见 `mobile/assets/fonts/README.md`。

更新时先备份 SQLite（使用 SQLite backup API，避免直接复制正在写入的数据库），
在新目录上传程序和 Web 产物，检查题目 ID 兼容性并运行测试，再切换 current 链接。
回滚程序时切回旧发布目录，检查 `nginx -t` 后重载 Nginx、重启 `dentstudy`；
不要为回滚程序而覆盖用户数据库。

基本验收：HTTPS 首页、`/api/health`、`/api/v1/questions`；
证书续期演练：`/opt/certbot-venv/bin/certbot renew --dry-run`。
上线可访问不代表支付、邮件验证码或题目医学审核已完成；这些仍需独立实施。

## 可选 Docker 部署方案（当前服务器未使用）

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
