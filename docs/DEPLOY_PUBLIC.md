# DentStudy 公网部署

本项目已准备 Render Blueprint：一个 API Web Service 和一个 Flutter Web Web Service。前端会加载综合题库，后端使用持久化 SQLite 数据盘保存账号、笔记、收藏和复习事件。

## 上线前必须完成的事情

1. 将最新代码推送到 GitHub 仓库的 `main` 分支。
2. 注册或登录 Render，选择 `New → Blueprint`，连接 `stein-wang0226/dentstudy-mvp`，让 Render 使用根目录的 `render.yaml`。
3. API 服务需要启用持久磁盘。Render 文档说明持久磁盘用于保存 SQLite 数据，但带磁盘的服务需要付费计算计划；免费实例不适合保存用户数据。
4. 第一次创建后记下两个服务的真实域名。若 API 服务名称被 Render 改写，需要把 `deploy/web.Dockerfile` 中的 `API_URL` 改成真实 API HTTPS 地址，再重新部署前端。
5. 在 API 服务的环境变量中设置：
   - `DENTSTUDY_DB=/var/data/dentstudy.sqlite3`
   - `DENTSTUDY_BANK=/app/mobile/assets/all_questions.json`
   - `ALLOWED_ORIGINS=https://你的前端域名`
6. 在前端 Dockerfile 中，将 `https://dentstudy-api.onrender.com` 换成真实 API 地址。前端的 API 地址是编译期参数，改完必须重新部署前端。
7. 部署完成后依次检查 `https://你的-api域名/health` 和 `https://你的-api域名/v1/questions`，再打开前端域名注册一个测试账号，验证登录、收藏、笔记、错题和跨浏览器同步。

## 自定义域名

在 Render 的前端服务中添加自己的域名，并按控制台提示配置 DNS。配置完成后，把 `ALLOWED_ORIGINS` 改成带 `https://` 的最终域名，不能保留 `*`。

## 题库发布要求

当前综合题库含原有修复学题库和牙周病学资料整理稿。牙周题目仍是 `draft`，没有经过教材版本、页码和医学教师复核。正式面向公众前，应把题目审核为 `approved`，使用已核实的教材出处和来源记录，并单独生成正式发布文件。

## 上线后的必要工作

- 为 API 增加限流、登录失败保护、密码重置、邮箱验证、注销和数据导出。
- 把 SQLite 迁移到 PostgreSQL；当前持久盘方案适合小规模 MVP，不能作为高并发长期方案。
- 配置备份、监控、错误告警和恢复演练。
- 为 VIP 支付增加 Apple/Google 收据的服务端校验。客户端本地 entitlement 不能作为生产计费依据。
- 前端使用 HTTPS API；不要把数据库、令牌、服务密钥或用户日志提交到 Git。
