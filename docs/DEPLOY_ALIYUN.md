# DentStudy 阿里云 ECS 部署

## 当前线上部署（2026-10-15）

实际服务器使用宿主机 Nginx + `dentstudy.service`，不是下面的 Docker 方案。
正式入口为 `https://dentstudy.uno`，HTTP 自动跳转 HTTPS。`www` DNS 仍暂停。

- 客户端版本：`0.2.16`（真实磨砂玻璃卡片、独立背景配色、仅新注册账号弹出资料完善）；综合题库 3520 道，原有 ID 全部保留。
- 后端：`/opt/dentstudy-current` 指向 `/opt/dentstudy-releases/20261015-avatar-fix-v0213`。
- 前端：`/var/www/dentstudy-current` 指向 `/var/www/dentstudy-releases/20261015-glass-fix-v0216`。
- 数据库：`/var/lib/dentstudy/dentstudy.sqlite3`，更新程序不能替换此文件。
- 用户投稿：`/var/lib/dentstudy/question-bank-submissions/`，仅服务端进程可读写，不能映射到 Nginx 静态目录；备份时须与 SQLite 一起保留。
- 旧代码 `/opt/dentstudy`、旧网页 `/var/www/dentstudy` 均保留。
- 更新前的数据库与配置备份：`/opt/backups/dentstudy-20261013`，数据库已验证完整性。
- HTTPS 使用 Let's Encrypt，`dentstudy-certbot.timer` 每天检查两次续期，续期成功后检查并重载 Nginx。
- `/.well-known/acme-challenge/` 继续使用 `/var/www/dentstudy`，不要随发布删除此目录。

配置模板：`deploy/nginx.ecs-https.conf`、`deploy/dentstudy-ecs-override.conf`、
`deploy/dentstudy-certbot.service` 和 `deploy/dentstudy-certbot.timer`。
构建 Web 时使用 `--no-web-resources-cdn --dart-define=API_URL=/api`
及 `--dart-define=QUESTION_BANK_ASSET=assets/all_questions.json`。
发布时同时传入 `--dart-define=APP_VERSION=0.2.16` 和
`--dart-define=BUILD_TIME=实际北京时间`，在“我的”显示版本与更新时间。
当前 GitHub workflow 只做检查，不会自动部署；代码推送后仍需单独构建和上传。

0.2.16 验收：已有账号退出后重新登录，不自动打开资料完善；新账号注册成功后打开资料完善，可跳过，之后仍可在“我的”手动编辑。
我的 → 主题与外观 → 自定义，主色选择青绿、背景选择玫瑰；开启玻璃质感，检查页面左右、卡片背后均为玫瑰背景，切换主色不应改变背景。
今日、题库、章节、题本、学情和逐题回顾的卡片使用局部裁剪的真实背景模糊、透明渐变和玻璃高光；关闭后恢复实色卡片。
配色与玻璃设置仍仅保存在本机；无新增依赖、后端修改、数据库迁移或同步协议变化。
回归覆盖老账号登录、新注册跳过资料、背景像素独立性、玻璃裁剪与跨页设置保留；手机与桌面尺寸已做视觉检查。
验证：Flutter 静态检查、29 项客户端测试、24 项后端测试通过；Chrome 通过 6 项交互与渲染测试，偏好重启测试仅由原生测试运行器覆盖。
玻璃效果为可选设置，低性能设备上的滚动流畅度仍需真机观察；如有卡顿，可关闭玻璃质感恢复实色卡片。

0.2.15 历史验收：我的 → 主题与外观 → 试用松绿、橄榄、洋红、石墨；自定义 → 分别选择主色与淡背景；
开启玻璃质感，查看半透明高光卡片和磨砂导航，再切换页面、重开应用确认设置保留。配色与外观仅存本机偏好，不进入学习事件同步。
此版本磨砂模糊集中于固定导航，滚动卡片使用透明渐变、高光边框与轻阴影；0.2.16 已改为真实卡片模糊。
个人资料卡仅保留退出登录；已移除手动同步、导入访客记录及待同步计数。账号自动同步继续运行。
此版本手动登录或注册成功后均弹出资料完善；0.2.16 已修复为仅新注册后弹出。
本次仅更新前端，无数据库迁移；静态检查、25 项客户端测试通过；Chrome 额外通过配色/玻璃跨页交互和资料跳过测试。

0.2.14 验收：作者账号 → 我的 → 作者管理，只展示三个紧凑入口；
用户目录保留总人数，题库投稿箱保留投稿份数。点击分别打开独立列表，支持刷新、加载失败重试和空状态；
返回“我的”后更新数量。普通账号不显示作者管理。列表按可视范围构建，避免一次渲染大量条目。
本次仅更新前端，后端和数据库无需迁移；Flutter 静态检查及现有客户端测试通过。

0.2.13 验收：我的 → 编辑资料 → 从图库上传 → 拖动/缩放正方形裁剪 → 使用此头像 → 保存；
上传照片和预设头像共享唯一选中值，取消裁剪不替换原头像。
题目讨论 → 自己的评论 → 删除并确认；他人的评论不能删除，已有回复保留。
作者账号 → 我的 → 评论管理 → 查看发布者、题目、正文、时间，可分页和跳转题目；普通账号无此入口，后端同样拒绝访问。
登录/注册 → 记住密码 → 成功后由浏览器或系统密码管理器决定是否弹出保存提示；普通偏好中不保存密码。
本版给评论表新增 `deleted_at` 字段，删除时清除正文和赞踩。现有学习事件不变。
验证：Flutter 静态检查、22 项客户端测试、24 项后端测试；另在 Chrome 运行头像解码及裁剪导出回归测试。

0.2.12 验收：我的顶部个人资料卡 → 编辑 → 从图库上传头像 → 保存，重新打开页面和题目讨论确认头像；
题目工具栏 → 讨论 → 写评论、回复、赞踩（再次点击取消，赞踩互斥），刷新确认数量和选择仍保存；
讨论标题显示去重后的参与人数；作者账号 → 我的 → 用户目录标题显示实际注册账号总数。
头像会在设备端居中裁剪为 256×256 PNG；原图不会上传。原有预设头像继续可用。
本版仅新增 `comment_votes` 表和评论表 `parent_id` 字段，原事件同步与学习排期不变。
验证：Flutter 静态检查、21 项 Flutter 测试、23 项后端测试通过。

0.2.9 的验收路径：我的 → 导入题库 / 投稿 → 选择符合模板的 JSON；
未登录时只允许本地导入，登录后才可投稿；作者账号可见“题库投稿箱”，普通账号不可见其他用户投稿；
今日首页 → “本网站无任何商业用途，请放心使用。”；
个人页不应出现 VIP、开通、恢复购买或支付入口；
顶部右侧 → 联系作者 → 邮箱或微信二维码；
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
