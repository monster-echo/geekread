# 内容合规审核（运维手册）

> 目标：翻译链路与阅读出站都不下发违法违规内容；人工处置可闭环下架并清理缓存。
> 适用范围：`backend/`（Next.js 专属后端）。

## 1. 能力概览

| 层 | 行为 | 代码位置 |
|---|---|---|
| 阅读出站 | `stories` / `items` / `tree` 返回前过滤：黑名单命中 + 本地关键词（可选叠加外部审核） | `lib/content-filter.ts`、各 route |
| 翻译入口 | 逐条审核；命中返回 `{ error: "blocked" }`，**不调模型、不写缓存、不扣配额**；story 被拉黑则整批拦截 | `app/api/translate/route.ts` |
| 摘要入口 | 标题/正文/评论命中或 story 被拉黑 → `403 content_blocked`，不生成不返回 | `app/api/reader/summarize/route.ts` |
| 人工处置 | 管理接口写 `BlockedContent` 黑名单，并清理对应翻译/摘要缓存 | `app/api/reader/moderation/route.ts` |
| 审核引擎 | 本地词库 + 可选 HTTP 内容安全服务；结果短缓存 | `lib/moderation.ts` |

未命中关键词的软性违规（涉政、隐喻等）建议通过外部审核服务或人工举报处置覆盖；**本地词库只是基线**。

## 2. 配置

见 `.env.example`「内容合规审核」段：

| 变量 | 说明 |
|---|---|
| `MODERATION_MODE` | `off` / `keyword` / `http` / `keyword+http`。默认 `keyword`；配置了 `MODERATION_HTTP_URL` 会自动叠加 http |
| `MODERATION_KEYWORDS_PATH` | 词库路径，默认 `data/moderation-keywords.json`（镜像已内置该目录） |
| `MODERATION_HTTP_URL` / `_TOKEN` / `_TIMEOUT_MS` | 外部审核服务地址、Bearer token、超时（默认 3000ms，上限 10s） |
| `MODERATION_FAIL_MODE` | 外部服务故障时 `open`（默认，放行并告警）或 `closed`（拦截并告警） |
| `OUTBOUND_FILTER` | 出站过滤强度：默认跟随审核模式；`keyword+http` 会对每条列表/评论调用外部服务（**成本高，慎开**） |
| `OPS_TOKEN` | 审核管理接口 token；未设置回退 `WARM_CACHE_TOKEN`；两者都空则管理接口禁用 |

> 词库格式：`{ "version": 1, "categories": { "<类别>": ["词条", ...] } }`。
> 中文词条按 NFKC+小写+去零宽+去空格标点后的**包含**匹配；含英文字母的词条按**单词边界**匹配。

## 3. 外部审核服务协议

`POST ${MODERATION_HTTP_URL}`，请求：

```json
{ "texts": ["待审文本1", "待审文本2"] }
```

响应（批量，长度须与 texts 一致）：

```json
{
  "results": [
    { "flagged": false, "labels": [] },
    { "flagged": true,  "labels": ["porn"], "reason": "adult" }
  ]
}
```

也支持单条 `{"flagged":true,"labels":[...]}`（仅当 texts 长度为 1）。非 2xx/结构不符视为故障，按 `MODERATION_FAIL_MODE` 处理。

接入云服务时建议用一层极薄的适配函数/服务（例如阿里云内容安全、腾讯云天御、华为），保持本协议不变，便于切换供应商。

## 4. 管理接口

鉴权：`?token=<OPS_TOKEN>` 或 `Authorization: Bearer <OPS_TOKEN>`。

```bash
# 举报列表（按时间倒序，含 reviewedAt）
curl -s "https://<host>/api/reader/moderation?token=$OPS_TOKEN&view=reports&limit=100"

# 黑名单
curl -s "https://<host>/api/reader/moderation?token=$OPS_TOKEN&view=blocks"

# 直接下架（comment 或 story）
curl -s -X POST "https://<host>/api/reader/moderation?token=$OPS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"action":"block","kind":"comment","targetId":12345678,"reason":"illegal"}'

# 举报处置：下架（会把举报标记为已处理并清缓存）
curl -s -X POST "https://<host>/api/reader/moderation?token=$OPS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"action":"resolve","reportId":42,"decision":"block","reason":"porn"}'

# 举报处置：忽略
curl -s -X POST "https://<host>/api/reader/moderation?token=$OPS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"action":"resolve","reportId":42,"decision":"dismiss"}'

# 解封（误判恢复）
curl -s -X POST "https://<host>/api/reader/moderation?token=$OPS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"action":"unblock","kind":"comment","targetId":12345678}'
```

## 5. 上线步骤

1. 部署前先跑迁移（容器启动时已自动 `prisma migrate deploy`；手工部署需执行）：新增 `BlockedContent` 表与 `Report.reviewedAt` 字段。
2. 重新构建镜像（`Dockerfile` 已 `COPY data ./data`，词库随镜像分发）。
3. 配置 `OPS_TOKEN` 与词库/外部服务 env 后重启。
4. 验证：
   - `GET /api/reader/stories` 正常返回且 `items` 完整；
   - 用测试句（如含词库词条）调 `/api/translate` → 该条返回 `error:"blocked"`，且 `remainingTranslations` 不因被拦条数减少；
   - 管理接口下架一条测试评论 → `items`/`tree` 立即不再下发，翻译缓存被清理。
5. 观察日志：`[moderation] blocked provider=... labels=... hash=...`（只记 hash，不记原文）。

## 6. 已知边界

- 关键词只能覆盖显式违规；软性/隐喻内容需外部审核或人工。
- 黑名单按 HN item id 生效；客户端若手工构造文本直接调翻译接口，仍需文本审核兜底（当前已做关键词/外部审核，但无 item id 无法套用黑名单）。
- 翻译缓存按原文文本清理；HN 内容未落本地缓存时（长尾评论）可能清不到，需等其回源后二次处置。
- 管理接口目前无分页游标与审计表；处置记录先在应用日志/`BlockedContent.createdAt` 留痕，规模化后建议补审核后台与审计表。