# 极客译读 · 专属后端

HN 代理 + 沉浸翻译 + 配额 + Pro 权益验签。极客译读客户端专属，与 MobileStarter 共享 server 解耦。

## 快速开始

```bash
cp .env.example .env.local   # 至少填 DATABASE_URL、MODEL_API_URL/KEY/NAME 与 ENTITLEMENT_SIGNING_SECRET
docker compose up -d --build # postgres + backend（启动自动 prisma migrate deploy）
npm install
npm run dev                  # http://localhost:8787（内置调度器仅生产自动启用）
```

存储：PostgreSQL 唯一持久层（文章/评论/翻译/摘要/配额/举报/内容黑名单）。
无 `DATABASE_URL` 时自动回退内存（仅 dev/test）。生产内置 60s 预热调度器（AIMD 自适应）。

## 内容合规审核

翻译/摘要入口与阅读出站（列表/条目/评论树）均接入内容审核，命中即**不下发、不翻译、不写缓存、不扣配额**：

- 基线：本地敏感词库 `data/moderation-keywords.json`（`MODERATION_KEYWORDS_PATH` 可覆盖）；
- 可选：外部内容安全服务 `MODERATION_HTTP_URL`（协议与部署见 [docs/ops/moderation.md](../docs/ops/moderation.md)）；
- 人力处置：违规内容写入 `BlockedContent` 黑名单，并联动清理翻译/摘要缓存；
- 配置项见 `.env.example` 的「内容合规审核」段。

## 接口

- `GET  /api/reader/stories?type=top|latest` → `{ items, cached, stale, blocked? }`（`blocked`=本次过滤条数）
- `POST /api/reader/items` `{ ids }` → `{ items, cached, stale, blocked? }`（被下架条目以 `null` 占位）
- `POST /api/reader/tree` `{ storyId }` → `{ items, cached, stale, blocked? }`（story 被下架时返回空树 + `blocked:true`）
- `POST /api/translate` `{ entries:[{key,text}], targetLanguage }`，头 `x-install-id`（必填）、`Authorization: Bearer <entitlement>`（Pro）→ `{ results, remainingTranslations?, blocked? }`（命中条目 `error:"blocked"`）
- `GET/POST /api/reader/moderation?token=...` → 审核管理（举报列表/下架/解封/处置），需 `OPS_TOKEN`（回退 `WARM_CACHE_TOKEN`）

## 测试

```bash
npm test                     # vitest，内存模式，无需 PG/LLM
```

## 部署

`docker build -t geekread-backend .` → 任一容器平台（Vercel / 华为云 CCE）。国内部署需备案。
