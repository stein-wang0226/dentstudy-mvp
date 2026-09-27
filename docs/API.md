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

请求体限制 2 MB。无认证返回 401，校验失败 400。同步批次原子提交，一条无效则整个批次回滚。不同账号的事件使用复合主键隔离。

题目 JSON 模板见 `mobile/assets/questions.json`。主要字段：

- `id` 为不可变内容版本 ID；`subject/chapter/topics/tags` 支撑学习检索。
- `modes`：考研、本科期末、执医；研究生和助理医师细分用标签筛选。
- `type`：A1/A2/A3/A4/B/简答题/案例分析；共用题干题型提供 `groupId/sharedStem`。B 型同组共用 `options`。
- `answer`：客观题为选项键，主观题为 null，主观题提供 `rubric`。
- `paperId/paperName/durationMinutes/order/points` 定义试卷、时长、顺序与分值。
- `school/year/sourceType/sourceUrl/license` 记录来源；真实院校试题不能用演示元数据代替。
- `citation`：publisher/title/edition/chapter/page/verified；正式发布需核实。
- `reviewStatus/reviewer/reviewedAt`：正式导入必须为 approved 并有审核记录。

数据库当前只有用户、会话、事件三张表；题库为经校验的版本化 JSON。已有 Web 后端可保持此 API 契约，用数据库题库表替换 JSON，并以 PostgreSQL 持久化事件。
