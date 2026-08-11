# 极客译读 · 专属后端

HN 代理 + 沉浸翻译 + 配额 + Pro 权益验签。极客译读客户端专属，与 MobileStarter 共享 server 解耦。

## 运行

```bash
cp .env.example .env.local   # 至少填 MODEL_API_URL/KEY/NAME 与 ENTITLEMENT_SIGNING_SECRET
npm install
npm run dev                  # http://localhost:8787
```

无 `REDIS_URL` 时自动回退内存缓存/配额（仅 dev）。

## 接口

- `GET  /api/reader/stories?type=top|latest` → `{ ids, cached, stale }`
- `POST /api/reader/items` `{ ids }` → `{ items, cached, stale }`（评论树客户端递归调用本接口）
- `POST /api/translate` `{ entries:[{key,text}], targetLanguage }`，头 `x-install-id`（必填）、`Authorization: Bearer <entitlement>`（Pro）→ `{ results, remainingTranslations? }`

## 测试

```bash
npm test                     # vitest，内存模式，无需 Redis/LLM
```

## 部署

`docker build -t geekread-backend .` → 任一容器平台（Vercel / 华为云 CCE）。国内部署需备案。
