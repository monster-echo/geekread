# 后端 Prisma + PostgreSQL 持久化：服务端全接管

日期：2026-08-18
状态：已确认（设计经用户逐节确认）

## 1. 背景与目标

现状：Next.js 后端的读路径依赖 Hacker News 上游 API（经 proxy.0x2a.top 加速、失败回退直连），
Redis 做 SWR 缓存（fresh/stale TTL）+ 翻译缓存（30 天 TTL）+ 摘要缓存 + 每日配额计数 +
举报列表。生产缺 Redis 直接抛 `redis_not_configured`。

目标：

1. 手机端所有请求由服务端本地（Postgres）秒回，与 HN 是否可达无关
2. 文章、评论、翻译、摘要永久落库，HN 降级为后台摄取源
3. Redis 整个下掉，部署只剩 backend + postgres 两个容器
4. API 签名不变，客户端零改动

## 2. 决策记录

### 2.1 存储选型：Postgres 全替换 Redis

调研结论（见 §9 来源）：数据集能装进内存时，Postgres（合理配 `shared_buffers`）
缓存命中率 ~98%+、延迟接近 Redis；Redis 优势（亚毫秒 p99、边缘分布）对单服务器小体量
应用无意义。本应用数据量（top/latest 列表 + top30 文章各 ≤200 评论 + 翻译）为几十 MB 级。
且翻译/摘要需要永久保存（Redis 30 天 TTL 过期即丢，重复翻译浪费 LLM 成本）。
运维上少一个容器、少一种故障模式。

### 2.2 同步模式：方案 A（cron 预热 + 长尾读时回源一次）

- 读路径永远先查 Postgres：命中直接返回（后台异步刷新）；未命中（长尾文章）回源
  HN 拉一次并落库，之后永久本地
- top50/latest50 + top30 文章评论树靠内置调度器预热，覆盖 95%+ 真实阅读量
- HN 挂了不影响已落库内容；仅"从未落库且 HN 不可达"的文章首次打不开

### 2.3 调度：后端进程内置（1 分钟间隔）+ AIMD 自适应

不依赖宿主 cron，Next.js `instrumentation.ts` 的 `register()` 起内置调度器。
触发 HN 限制时自动降速、恢复后逐级升回（§5.4）。

## 3. 架构与数据流

```
手机端 ──> Next.js API ──> Postgres（唯一存储，永久）──命中──> 秒回
                              │未命中（长尾）
                              └──> HN 回源一次 ──> 落库 ──> 返回
内置调度器（60s tick）──> 刷新列表 + 文章头 + 增量评论树（预算制）
```

## 4. 数据模型（Prisma schema 草案）

| 表 | 关键字段 | 说明 |
|---|---|---|
| `HnItem` | `id`(PK), type, by, time, text, url, title, score, descendants, kids Int[], deleted, dead, raw Json, `fetchedAt` | 文章+评论统一表（HN 同构 item）；`raw` 存原始 JSON 兜底未映射字段；`fetchedAt` 做 SWR |
| `StoryList` | `type`(PK: `top`/`latest`), ids Int[], `fetchedAt` | 两个有序列表 |
| `Translation` | `hash`(unique), lang, source, result, `createdAt` | hash = sha256(version + \0 + model + \0 + lang + \0 + text)，与现 Redis key 同构；永不过期，换模型靠 hash 隔离 |
| `Summary` | `hash`(unique), storyId, lang, result, `createdAt` | hash 含 storyId；永久 |
| `QuotaUsage` | PK(day, clientId), used | `INSERT ... ON CONFLICT DO UPDATE SET used = used + 1 RETURNING used` 原子计数，优于现 Redis 版进程内锁方案 |
| `Report` | 自增 id, storyId, commentId, reason, text, installId, ts | 替代 Redis list `geekread:reports` |

## 5. 同步与调度

### 5.1 触发方式

Next.js `instrumentation.ts` 的 `register()`（服务进程启动时执行一次）里起 `setInterval`：
- 周期 60s，启动延迟 10s 错峰
- `NODE_ENV !== 'production'` 时不自动起（dev 手动打 warm 接口）
- `/api/reader/warm`（token 保护不变）保留，用于手动触发与运维验证

### 5.2 每 tick 做什么（增量分层）

| 层 | 频率 | 内容 | HN 请求量 |
|---|---|---|---|
| 列表 | 每 tick | top + latest 列表 ID | 2 |
| 文章头 | 每 tick | top30 文章本体（score/descendants 变化最快） | ~30 |
| 评论树 | 增量触发 | 只刷 `descendants` 增长了的树 + 按 `fetchedAt` 最老优先轮转补刷，每 tick 预算上限 5 棵 | ≤5×~40 |

稳态 ≈ 32~230 请求/分钟（0.5~4 req/s），对 CDN 化的 firebase API 安全。
热门文章新评论 1~2 分钟可见；冷门树靠轮转最终刷新。

### 5.3 预热范围（env 参数化）

`WARM_TOP_N=50`、`WARM_LATEST_N=50`、`WARM_TREE_N=30`、`WARM_TREE_BUDGET=5`。

### 5.4 自适应调节（AIMD）

探测信号（滑动窗口 = 最近 100 个 HN 请求）：
- `429` 或 `Retry-After` 头 → 立即判定受限
- 错误率 > 30%（超时/5xx 计入）→ 判定上游不稳

降速（乘性，立即执行）：间隔 ×2 逐级 60s→120s→300s→600s（封顶）；树预算 5→2→0；
`Retry-After` 存在时直接遵守。

恢复（加性，连续 10 个 tick 无错误才动一次）：间隔降一级回 60s；树预算 0→2→5。

读路径不受调度器降速影响：用户请求该回源还是回源（量小、8s 超时快速失败）。
最坏情况 = 数据旧一点，不会报错。状态机为模块内小对象（level 0~3 + 窗口计数），
不持久化，进程重启从 level 0 重新探测。

## 6. 读路径改造（API 签名不变）

- **stories**：PG 读 `StoryList`；`fetchedAt` 超 fresh(3min) → 返回旧值 + 后台刷新；
  超 stale(20min) → 同步刷一次，失败仍返回旧值
- **items / tree**：批量查 `HnItem`；缺的 id 回源 HN 并 upsert（一次）；已有但
  `fetchedAt` 老的 → 返回 + 后台刷新。tree 的 BFS/`MAX_COMMENTS=200` 逻辑保持
- **translate / summarize**：hash 查 PG，命中直接回；未命中 → LLM → 落 PG（无 TTL）
- **quota / report**：换 PG 实现，语义不变（配额 rollback = `used - 1`）
- **回源降级**：PG 有数据永远返回 PG（哪怕很老）；PG 无数据且 HN 失败 → 保持现有报错

## 7. 部署

- `backend/docker-compose.yml`：`postgres:16-alpine`（volume 持久化）+ backend；
  backend 入口 `npx prisma migrate deploy && npm start`
- Dockerfile 增加 prisma generate 步骤；迁移文件进 repo
- env：新增 `DATABASE_URL`；删除 `REDIS_URL`、`TRANSLATION_CACHE_TTL_SECONDS`
- 旧 Redis 数据不迁移（TTL 数据无价值；翻译缓存丢了重翻一次即可）
- dev：本地 docker 起 PG 或 `DATABASE_URL` 指远程库

## 8. 测试策略

- 现有 vitest 模式保持（mock 全局 fetch + `vi.resetModules()`）；`lib/storage` 的
  mock 边界换成新的 PG 数据访问层
- 新增单测：SWR 刷新触发、回源 upsert、配额原子计数语义、AIMD 状态机转移
  （mock prisma client / 窗口计数）
- 真库验证走部署后 smoke（warm 接口 + 手机端实测）

## 9. 不做的事

- 客户端任何改动（API 签名不变）
- Redis → PG 数据迁移
- 用户账户/订单系统接入（仍是 MobileStarter 那套）

## 10. 调研来源

- [Can Postgres replace Redis as a cache? — Raphael De Lio](https://medium.com/redis-with-raphael-de-lio/can-postgres-replace-redis-as-a-cache-f6cba13386dc)
- [I Replaced Redis with PostgreSQL — DEV Community](https://dev.to/polliog/i-replaced-redis-with-postgresql-and-its-faster-4942)
- [Redis is fast — I'll cache in Postgres — Dizzy Zone](https://dizzy.zone/2025/09/24/Redis-is-fast-Ill-cache-postgres/)（及 [Lobsters 讨论](https://lobste.rs/s/liau26/redis_is_fast_i_ll_cache_postgres)）
- [Stale-while-revalidate caching pattern — OneUptime](https://oneuptime.com/blog/post/2026-03-31-redis-stale-while-revalidate/view)
- [High-Performance Distributed Caching with .NET and Postgres — Microsoft DevBlogs](https://devblogs.microsoft.com/dotnet/high-performance-distributed-caching-dotnet-postgres-azure/)
