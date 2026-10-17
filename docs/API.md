# API v1 与数据结构

API 默认 `http://127.0.0.1:8787`，JSON UTF-8。私有接口使用 `Authorization: Bearer <token>`。token 在数据库只存 SHA-256 摘要，客户端使用系统安全存储；密码使用随机盐和 PBKDF2-SHA256。会话有效期 30 天。

| 方法 | 路径 | 输入 / 输出 |
| --- | --- | --- |
| GET | `/health` | 服务版本与状态 |
| GET | `/v1/questions` | 完整题库，用于本地缓存 |
| POST | `/v1/auth/register` | `{email,password}` → `{token,userId,email}` |
| POST | `/v1/auth/login` | 同上 |
| POST | `/v1/auth/logout` | `{}`，撤销当前 token |
| POST | `/v1/sync` | `{events:[...]}`，最多 500 条；返回完整快照 |
| GET | `/v1/state` | 返回当前账号快照 |
| POST | `/v1/question-bank-submissions` | 登录后提交 `{filename,content}`；仅 `.json`，原文件最大 12 MB |
| POST | `/v1/ai/question-bank/prepare` | 登录后提交 `{text,name,subject,chapter,mode}`，将 Word/TXT 已提取的文字整理为待审核 JSON；最多 6 万字、每账号每日 3 次 |
| POST | `/v1/assistant/chat` | 当前仅配置的作者账号可用的“小齿”聊天入口 `{message,history?}`；其他账号返回“小齿正在升级中···”。单条消息最多 1000 字、上下文最多 6 条 |
| GET | `/v1/question-bank-submissions` | 登录后查看自己的投稿；配置的作者账号可查看全部投稿元数据 |
| GET | `/v1/admin/question-bank-submissions/{id}` | 仅作者可下载一份投稿的原始 JSON；响应不缓存且不会经静态目录公开 |
| GET / POST | `/v1/profile` | 当前账号资料；保存 `{nickname,avatar,university}`。头像兼容预设键或客户端裁剪的 PNG data URI（512 KB、512 像素以内） |
| GET | `/v1/questions/{id}/comments` | 返回 `comments`、去重后的 `participantCount` 和 `totalCount`；携带登录 token 时附带每条评论的 `myVote` |
| POST | `/v1/questions/{id}/comments` | `{body,parentId?}`；登录后评论或回复，回复限定同一题目 |
| POST | `/v1/comments/{id}/vote` | `{value:1/-1/0}` 表示赞/踩/取消；同账号仅保留一种评价，返回 `likes,dislikes,myVote` |
| GET | `/v1/admin/users` | 仅作者可见用户资料和邮箱；返回 `users`（最多 1000 条）、实际注册账号总数 `totalCount` |
| POST | `/v1/comments/{id}/delete` | `{}`；仅发布者可删除自己的评论。清除正文与赞踩，保留他人回复所需的占位关系；评论列表返回 `canDelete`、`deletedAt` |
| GET | `/v1/admin/comments?offset=0` | 仅作者可见评论管理，含发布者邮箱、昵称、题目 ID/题干/章节、评论和时间；每页 50 条，返回 `totalCount`、`nextOffset` |

头像由客户端提供可拖动、缩放的正方形裁剪页，确认后导出为 256×256 PNG，再通过资料接口保存。
登录表单的“记住密码”使用浏览器或系统密码管理器的 Autofill 功能；本地偏好仅保存是否启用和邮箱，不保存明文密码。

快照：`events` 原始日志，`states` 每题排期/题本状态，`attempts` 用于统计的作答记录，`plan` 含今日 due、新题与 newLocked，`settings` 为账号级学习目标。

`/v1/sync` 可同时带 `settings`：

```json
{
  "events": [],
  "settings": {
    "dailyNewLimit": 20,
    "dailyReviewTarget": null,
    "updatedAt": "2026-09-26T08:30:00.000Z"
  }
}
```

`dailyNewLimit` 为 0–1,000,000；`dailyReviewTarget` 为 0–200，`null` 表示无限制。服务端按 `updatedAt` 保留较新的设置。

答题事件：

```json
{
  "id": "device-random-unique-event-0001",
  "questionId": "demo-001",
  "at": "2026-09-25T08:30:00.000Z",
  "kind": "review",
  "value": {"answer":"B", "grade":"mastered", "mode":"practice"}
}
```

`kind` 还可为 `favorite`（value 为 bool）、`note`（字符串最多 10000 字）、`removeWrong`（null）。grade 为 wrong/guessed/mastered；mode 为 practice/review/exam。主观题 answer 为用户书写的文本。事件时间必须带时区，不得超过服务器当前时间 5 分钟。超时请求可按原事件 ID 原样重试。

常规请求体限制 2 MB；题库投稿允许原文件最大 12 MB（为容纳 JSON 传输封装，请求上限 16 MB）；AI 整理请求上限 512 KB，原文字上限 6 万字；小齿聊天请求上限 24 KB。除公开的小齿聊天和题目评论读取外，无认证返回 401；校验失败 400，AI 未配置、免费额度耗尽或服务器预算到顶返回 503。同步批次原子提交，一条无效则整个批次回滚。不同账号的事件使用复合主键隔离。

AI 整理使用服务器受限环境变量中的阿里云百炼 API Key，客户端、Git 和响应中都不携带密钥。只有用户在导入对话框显式点击“AI 智能整理”时，当前文字才会发送给模型；服务端不持久化原文或模型原始输出，只保存账号标识、调用时间、token 计数与预算金额用于限流。模型仅可提取原文中已有的题干、2–8 个选项和与选项一致的答案；不完整或答案不明确的条目会被丢弃，结果统一标为用户导入、待医学审核，不能进入公开题库。

小齿聊天当前仅配置的作者账号可用；其他账号在客户端点击会显示“小齿正在升级中···”，服务端也会拒绝此类请求。消息与最近最多 6 条临时上下文只在本次请求中发给模型；服务端不写入消息或回复，也不写入题库或学习事件。为实现作者账号的每日额度，服务端只保存账号标识、调用类别（闲聊/专业）与调用时间、token/预算计数；每个账号每天最多 10 句闲聊，口腔医学与备考问题不占该闲聊额度，站点仍保留全站预算保护。小齿只讨论人类口腔医学与口腔备考；无关话题会被温和引导回具体学习目标。它不能点击、上传、下载、跳转或改变网站，也不能协助未授权资料、版权规避或医疗诊断。

题库投稿先在客户端本地校验、合并至该设备的离线题库；登录后才会把原始 JSON 副本提交至服务端。服务端再次执行 `backend/bank.py validate` 校验，保存到 `DENTSTUDY_SUBMISSIONS` 指向的私有目录，不经 Nginx 对外提供。投稿文件只用于人工审核，用户须确保拥有分享权限，不得上传个人隐私、受限或来源不明的内容。`DENTSTUDY_ADMIN_EMAIL` 对应的账号可在客户端投稿箱查看文件名、题数、大小、时间及投稿邮箱，并可通过仅作者可用的下载接口将原始 JSON 保存到本地；下载响应为 `no-store`，不会生成公开链接。

用户自行导入的题库题目 ID 不属于服务端的官方题库。此类题目的作答、收藏、笔记等事件仅保留在该设备本地，不会进入 `/v1/sync`；这样既能正常练习，也不会被服务端按不存在的题目 ID 拒绝。官方题库题目的同步、事件 ID 与排期契约不变。

题目 JSON 模板见 `mobile/assets/questions.json`。主要字段：

- `id` 为不可变内容版本 ID；`subject/chapter/topics/tags` 支撑学习检索。
- `modes`：考研、本科期末、执医；研究生和助理医师细分用标签筛选。
- `type`：A1/A2/A3/A4/B/简答题/案例分析；共用题干题型提供 `groupId/sharedStem`。B 型同组共用 `options`。
- `answer`：客观题为选项键，主观题为 null，主观题提供 `rubric`。
- `paperId/paperName/durationMinutes/order/points` 定义试卷、时长、顺序与分值。
- `school/year/sourceType/sourceUrl/license` 记录来源；真实院校试题不能用演示元数据代替。
- `citation`：publisher/title/edition/chapter/page/verified；正式发布需核实。
- `reviewStatus/reviewer/reviewedAt`：正式导入必须为 approved 并有审核记录。

数据库当前含用户、会话、事件、学习设置、题库投稿元数据与不含原文的 AI 调用计量；运行题库仍为经校验的版本化 JSON。已有 Web 后端可保持此 API 契约，用数据库题库表替换 JSON，并以 PostgreSQL 持久化事件。
