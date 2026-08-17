# Prisma + PostgreSQL 持久化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 后端以 PostgreSQL 为唯一存储（文章/评论/翻译/摘要/配额/举报落库），手机端请求本地秒回，HN 降级为后台摄取源，Redis 整个下掉。

**Architecture:** Next.js API 读路径 PG-first（命中即返 + 后台刷新；未命中回源一次并 upsert）；进程内置 60s 调度器（增量分层预热 + AIMD 自适应退避）；所有 store 模块保留"无 DATABASE_URL 时内存回退"语义，现有 vitest 全部免 DB 通过。

**Tech Stack:** Next.js 16 + Prisma 6 + PostgreSQL 16 + vitest（现有）

**Spec:** `docs/superpowers/specs/2026-08-18-prisma-postgres-persistence-design.md`

**关键既有约定（实现者必读）：**
- 测试模式：`vi.resetModules()` + `delete process.env.REDIS_URL`（新代码改查 `DATABASE_URL`），依赖模块级内存回退，**测试不连任何数据库**
- `lib/http.ts` 提供 `json/errorResponse/requireString/safeErrorStatus`，所有路由已用
- hash 公式（翻译缓存 key，必须原样保留）：sha256(`version` + `\0` + `model` + `\0` + `lang` + `\0` + `text`)，version 默认 `v1`，model 取 `MODEL_NAME`
- 现有语义：`production()`（`NODE_ENV==='production'`）缺配置直接 throw；dev 返回 undefined 走内存

---

## 文件结构

**Create:**
- `backend/prisma/schema.prisma` — 六张表
- `backend/lib/db.ts` — Prisma 单例（生产缺 DATABASE_URL 抛 `pg_not_configured`，dev 返回 undefined）
- `backend/lib/hn-store.ts` — HnItem/StoryList 读写 + 内存回退
- `backend/lib/cache-store.ts` — 翻译/摘要读写 + 内存回退（签名同旧 storage.ts）
- `backend/lib/quota-store.ts` — 配额原子计数 + 内存回退
- `backend/lib/report-store.ts` — 举报落库 + 内存回退
- `backend/lib/hn-health.ts` — AIMD 状态机
- `backend/lib/sync.ts` — 预热 tick（列表/文章头/评论树增量）
- `backend/lib/scheduler.ts` — 自调度循环（间隔随 AIMD 变化）
- `backend/instrumentation.ts` — Next 启动钩子拉起调度器
- `backend/docker-compose.yml` — postgres + backend
- 测试：`test/hn-store.test.ts`、`test/cache-store.test.ts`、`test/quota-store.test.ts`、`test/hn-health.test.ts`、`test/sync.test.ts`

**Modify:**
- `backend/app/api/translate/route.ts` — import 换 cache-store/quota-store
- `backend/app/api/reader/summarize/route.ts`、`quota/route.ts`、`report/route.ts`、`warm/route.ts`
- `backend/lib/hacker-news.ts` — 内部重写 PG-first（对外签名不变）
- `backend/package.json`、`backend/Dockerfile`、`backend/.env.example`、`backend/README.md`
- `backend/test/hacker-news.test.ts`（最后一个用例改用 hn-store 测试钩子）
- `backend/test/routes/translate.test.ts`（import 路径换）

**Delete:**
- `backend/lib/storage.ts`、`backend/test/storage.test.ts`、`backend/warm-cache.cjs`

---

### Task 1: Prisma 脚手架 + schema + 首个迁移

**Files:**
- Create: `backend/prisma/schema.prisma`
- Modify: `backend/package.json`（deps：加 `prisma`、`@prisma/client`，删 `redis`）
- Modify: `backend/.env.local`（本地 dev 加 `DATABASE_URL`，指 5433 端口的本地 PG）

- [ ] **Step 1: 起本地开发 PG（5433 端口避免撞已有实例）**

```bash
docker run -d --name geekread-pg-dev -e POSTGRES_PASSWORD=dev -p 5433:5432 postgres:16-alpine
```

Expected: 容器运行，`docker ps` 可见。若已存在同名容器则 `docker start geekread-pg-dev`。

- [ ] **Step 2: 安装依赖**

```bash
cd backend && npm install @prisma/client prisma && npm uninstall redis
```

注意 `prisma` 放 dependencies（生产入口要跑 `prisma migrate deploy`）。

- [ ] **Step 3: 写 schema.prisma**

```prisma
// backend/prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

/// HN 条目（文章+评论统一表，HN 同构 item）。raw 存原始 JSON 兜底；
/// 富字段供 SQL 查询（树增量用 descendants，轮转用 type+fetchedAt）。
model HnItem {
  id          Int      @id
  type        String?
  by          String?
  time        Int?
  text        String?
  url         String?
  title       String?
  score       Int?
  descendants Int?
  kids        Int[]
  deleted     Boolean  @default(false)
  dead        Boolean  @default(false)
  /// HN 对已删除/不存在的 item 返回 null：missing=true 标记，读时还原为 null
  missing     Boolean  @default(false)
  raw         Json?
  fetchedAt   DateTime @default(now())

  @@index([type, fetchedAt])
}

/// top/latest 两个有序故事列表
model StoryList {
  type      String   @id
  ids       Int[]
  fetchedAt DateTime @default(now())
}

/// 翻译（永不过期；hash = sha256(version\0model\0lang\0text)，换模型靠 hash 隔离）
model Translation {
  id        Int      @id @default(autoincrement())
  hash      String   @unique
  lang      String
  source    String
  result    String
  createdAt DateTime @default(now())

  @@index([lang])
}

/// AI 摘要（永久）
model Summary {
  id        Int      @id @default(autoincrement())
  hash      String   @unique
  storyId   Int
  lang      String
  result    String
  createdAt DateTime @default(now())
}

/// 每日翻译配额（原子 upsert 计数）
model QuotaUsage {
  day      String
  clientId String
  used     Int      @default(0)

  @@id([day, clientId])
}

/// 内容举报（替代 Redis list geekread:reports）
model Report {
  id        Int      @id @default(autoincrement())
  storyId   Int
  commentId Int
  reason    String
  text      String   @default("")
  installId String
  ts        BigInt   @default(0)

  @@index([ts])
}
```

- [ ] **Step 4: .env.local 加本地 DATABASE_URL**

```bash
# backend/.env.local 追加一行：
DATABASE_URL=postgresql://postgres:dev@localhost:5433/postgres
```

- [ ] **Step 5: 生成迁移**

```bash
cd backend && DATABASE_URL=postgresql://postgres:dev@localhost:5433/postgres npx prisma migrate dev --name init
```

Expected: `prisma/migrations/<ts>_init/` 生成，`npx prisma generate` 自动执行，无错误。

- [ ] **Step 6: 提交**

```bash
git add backend/prisma backend/package.json backend/package-lock.json backend/.env.local
git commit -m "feat(db): Prisma 脚手架——六表 schema + init 迁移"
```

（`.env.local` 若被 gitignore 则跳过 add 该文件。）

---

### Task 2: lib/db.ts — Prisma 单例

**Files:**
- Create: `backend/lib/db.ts`

无独立测试（经由后续 store 的内存回退测试与部署 smoke 覆盖）。

- [ ] **Step 1: 写实现**

```ts
// backend/lib/db.ts
import { PrismaClient } from '@prisma/client';

let client: PrismaClient | undefined;
let startup: Promise<PrismaClient | undefined> | undefined;

function production(): boolean {
  return process.env.NODE_ENV === 'production';
}

/**
 * Prisma 单例。语义对齐旧 lib/storage.ts 的 redis()：
 * - 生产缺 DATABASE_URL → throw pg_not_configured（fail fast）
 * - dev/test 无 DATABASE_URL → undefined，调用方走内存回退（vitest 不连库）
 */
export async function db(): Promise<PrismaClient | undefined> {
  const url = process.env.DATABASE_URL?.trim();
  if (!url) {
    if (production()) throw new Error('pg_not_configured');
    return undefined;
  }
  if (!startup) {
    client = new PrismaClient({ log: ['error', 'warn'] });
    startup = client
      .$connect()
      .then(() => client)
      .catch((error) => {
        startup = undefined; // 失败不缓存，下次重连
        throw error;
      });
  }
  return startup;
}
```

- [ ] **Step 2: 类型检查**

```bash
cd backend && npx tsc --noEmit
```

Expected: 无错误。

- [ ] **Step 3: 提交**

```bash
git add backend/lib/db.ts
git commit -m "feat(db): Prisma 单例 db()——生产缺配置 fail fast，dev 内存回退"
```

---

### Task 3: lib/hn-store.ts — HN 条目/列表存储

**Files:**
- Create: `backend/lib/hn-store.ts`
- Test: `backend/test/hn-store.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
// backend/test/hn-store.test.ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('hn-store (in-memory)', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.DATABASE_URL;
    delete process.env.NODE_ENV;
  });

  it('upsert 后按 id 读回，保持插入语义', async () => {
    const { upsertItems, readItems } = await import('../lib/hn-store.js');
    await upsertItems([
      { id: 1, raw: { id: 1, type: 'story', title: 'a' } },
      { id: 2, raw: { id: 2, type: 'comment', text: 'c' } },
    ]);
    const rows = await readItems([1, 2, 3]);
    expect(rows.get(1)?.raw).toMatchObject({ id: 1, title: 'a' });
    expect(rows.get(2)?.raw).toMatchObject({ id: 2, text: 'c' });
    expect(rows.has(3)).toBe(false); // 未落库 ≠ missing
  });

  it('HN null（已删除）存为 missing，读回为 null 语义', async () => {
    const { upsertItems, readItems } = await import('../lib/hn-store.js');
    await upsertItems([{ id: 9, raw: null }]);
    const rows = await readItems([9]);
    expect(rows.get(9)?.raw).toBeNull();
    expect(rows.get(9)?.missing).toBe(true);
  });

  it('重复 upsert 覆盖旧值并刷新 fetchedAt', async () => {
    const { upsertItems, readItems } = await import('../lib/hn-store.js');
    await upsertItems([{ id: 1, raw: { id: 1, score: 1 } }]);
    await upsertItems([{ id: 1, raw: { id: 1, score: 2 } }]);
    const rows = await readItems([1]);
    expect(rows.get(1)?.raw).toMatchObject({ score: 2 });
  });

  it('StoryList 存取 roundtrip', async () => {
    const { saveStoryList, readStoryList } = await import('../lib/hn-store.js');
    await saveStoryList('top', [5, 6, 7]);
    const got = await readStoryList('top');
    expect(got?.ids).toEqual([5, 6, 7]);
    expect(await readStoryList('latest')).toBeUndefined();
  });

  it('oldestFetchedStories 只返回超过最小树龄的 story，按 fetchedAt 升序', async () => {
    const { upsertItems, oldestFetchedStories } = await import('../lib/hn-store.js');
    await upsertItems([
      { id: 1, raw: { id: 1, type: 'story' } },
      { id: 2, raw: { id: 2, type: 'comment' } },
    ]);
    await oldestFetchedStories; // import 就绪
    // id=1 刚写入，minAgeMinutes=60 时不应入选
    expect(await oldestFetchedStories(5, 60)).toEqual([]);
  });

  it('__testBackdateItem 把 fetchedAt 回拨（仅测试用）', async () => {
    const { upsertItems, oldestFetchedStories, __testBackdateItem } = await import('../lib/hn-store.js');
    await upsertItems([{ id: 1, raw: { id: 1, type: 'story' } }]);
    await __testBackdateItem(1, 120);
    expect(await oldestFetchedStories(5, 60)).toEqual([1]);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd backend && npx vitest run test/hn-store.test.ts
```

Expected: FAIL，模块不存在。

- [ ] **Step 3: 写实现**

```ts
// backend/lib/hn-store.ts
import { db } from './db';

/** HN 原始 item（null = HN 返回 null：已删除/不存在） */
export type HnRawItem = Record<string, unknown> | null;
export type ItemUpsert = { id: number; raw: HnRawItem };
export type ItemRow = { id: number; raw: HnRawItem; missing: boolean; fetchedAt: Date };

// ---- 内存回退（dev/test 无 DATABASE_URL；语义对齐旧 storage.ts）----
const memItems = new Map<number, { raw: HnRawItem; fetchedAt: Date }>();
const memLists = new Map<string, { ids: number[]; fetchedAt: Date }>();

type PrismaLike = NonNullable<Awaited<ReturnType<typeof db>>>;

/** HN raw JSON → HnItem 行字段（缺省 undefined 交由 Prisma 忽略） */
function rowFields(raw: HnRawItem) {
  if (raw === null) return { missing: true };
  const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined);
  const int = (v: unknown): number | undefined =>
    typeof v === 'number' && Number.isSafeInteger(v) ? v : undefined;
  const kids = Array.isArray(raw.kids)
    ? raw.kids.filter((k): k is number => typeof k === 'number' && Number.isSafeInteger(k))
    : [];
  return {
    type: str(raw.type),
    by: str(raw.by),
    time: int(raw.time),
    text: str(raw.text),
    url: str(raw.url),
    title: str(raw.title),
    score: int(raw.score),
    descendants: int(raw.descendants),
    kids,
    deleted: raw.deleted === true,
    dead: raw.dead === true,
    missing: false,
    raw: raw as object,
  };
}

export async function upsertItems(items: ItemUpsert[]): Promise<void> {
  if (items.length === 0) return;
  const client = await db();
  if (!client) {
    const now = new Date();
    for (const it of items) memItems.set(it.id, { raw: it.raw, fetchedAt: now });
    return;
  }
  await client.$transaction(
    items.map((it) =>
      client.hnItem.upsert({
        where: { id: it.id },
        create: { id: it.id, fetchedAt: new Date(), ...rowFields(it.raw) },
        update: { fetchedAt: new Date(), ...rowFields(it.raw) },
      }),
    ),
  );
}

export async function readItems(ids: number[]): Promise<Map<number, ItemRow>> {
  if (ids.length === 0) return new Map();
  const unique = [...new Set(ids)];
  const client = await db();
  if (!client) {
    const out = new Map<number, ItemRow>();
    for (const id of unique) {
      const hit = memItems.get(id);
      if (hit) out.set(id, { id, raw: hit.raw, missing: hit.raw === null, fetchedAt: hit.fetchedAt });
    }
    return out;
  }
  const rows = await client.hnItem.findMany({ where: { id: { in: unique } } });
  const out = new Map<number, ItemRow>();
  for (const r of rows) {
    out.set(r.id, {
      id: r.id,
      raw: r.missing ? null : (r.raw as HnRawItem),
      missing: r.missing,
      fetchedAt: r.fetchedAt,
    });
  }
  return out;
}

export async function readStoryList(type: string): Promise<{ ids: number[]; fetchedAt: Date } | undefined> {
  const client = await db();
  if (!client) {
    const hit = memLists.get(type);
    return hit ? { ids: hit.ids, fetchedAt: hit.fetchedAt } : undefined;
  }
  const row = await client.storyList.findUnique({ where: { type } });
  return row ? { ids: row.ids, fetchedAt: row.fetchedAt } : undefined;
}

export async function saveStoryList(type: string, ids: number[]): Promise<void> {
  const now = new Date();
  const client = await db();
  if (!client) {
    memLists.set(type, { ids, fetchedAt: now });
    return;
  }
  await client.storyList.upsert({
    where: { type },
    create: { type, ids, fetchedAt: now },
    update: { ids, fetchedAt: now },
  });
}

/** 树轮转候选：type=story 且 fetchedAt 早于 minAgeMinutes 的，最老优先。 */
export async function oldestFetchedStories(limit: number, minAgeMinutes: number): Promise<number[]> {
  const cutoff = new Date(Date.now() - minAgeMinutes * 60_000);
  const client = await db();
  if (!client) {
    return [...memItems.entries()]
      .filter(([, v]) => (v.raw as { type?: unknown })?.type === 'story' && v.fetchedAt < cutoff)
      .sort((a, b) => a[1].fetchedAt.getTime() - b[1].fetchedAt.getTime())
      .slice(0, limit)
      .map(([id]) => id);
  }
  const rows = await client.hnItem.findMany({
    where: { type: 'story', missing: false, fetchedAt: { lt: cutoff } },
    orderBy: { fetchedAt: 'asc' },
    take: limit,
    select: { id: true },
  });
  return rows.map((r) => r.id);
}

/** 仅测试用：把某 id 的 fetchedAt 回拨（验证 SWR 过期逻辑）。 */
export async function __testBackdateItem(id: number, minutesAgo: number): Promise<void> {
  const client = await db();
  if (!client) {
    const hit = memItems.get(id);
    if (hit) hit.fetchedAt = new Date(Date.now() - minutesAgo * 60_000);
    return;
  }
  await client.hnItem.update({
    where: { id },
    data: { fetchedAt: new Date(Date.now() - minutesAgo * 60_000) },
  });
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd backend && npx vitest run test/hn-store.test.ts
```

Expected: 6 passed。

- [ ] **Step 5: 提交**

```bash
git add backend/lib/hn-store.ts backend/test/hn-store.test.ts
git commit -m "feat(db): hn-store——HnItem/StoryList 读写 + missing 语义 + 内存回退"
```

---

### Task 4: lib/cache-store.ts — 翻译/摘要存储

**Files:**
- Create: `backend/lib/cache-store.ts`
- Test: `backend/test/cache-store.test.ts`

- [ ] **Step 1: 写失败测试（从旧 storage.test.ts 移植翻译/摘要部分）**

```ts
// backend/test/cache-store.test.ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('cache-store (in-memory)', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.DATABASE_URL;
    delete process.env.NODE_ENV;
  });

  it('caches and reads a translation', async () => {
    const { cacheTranslation, getCachedTranslation } = await import('../lib/cache-store.js');
    await cacheTranslation('hello', 'zh-Hans', '你好');
    expect(await getCachedTranslation('hello', 'zh-Hans')).toBe('你好');
    expect(await getCachedTranslation('bye', 'zh-Hans')).toBeUndefined();
  });

  it('translation key 隔离语言与模型（换 MODEL_NAME 后不命中）', async () => {
    process.env.MODEL_NAME = 'model-a';
    const { cacheTranslation, getCachedTranslation } = await import('../lib/cache-store.js');
    await cacheTranslation('hello', 'zh-Hans', '你好');
    process.env.MODEL_NAME = 'model-b';
    expect(await getCachedTranslation('hello', 'zh-Hans')).toBeUndefined();
  });

  it('empty translation is not cached', async () => {
    const { cacheTranslation, getCachedTranslation } = await import('../lib/cache-store.js');
    await cacheTranslation('hello', 'zh-Hans', '   ');
    expect(await getCachedTranslation('hello', 'zh-Hans')).toBeUndefined();
  });

  it('caches and reads a summary（永久，同 storyId+lang 只存一份）', async () => {
    const { cacheSummary, getCachedSummary } = await import('../lib/cache-store.js');
    await cacheSummary(42, 'zh-Hans', '要点');
    expect(await getCachedSummary(42, 'zh-Hans')).toBe('要点');
    await cacheSummary(42, 'zh-Hans', '更新后的要点');
    expect(await getCachedSummary(42, 'zh-Hans')).toBe('更新后的要点');
    expect(await getCachedSummary(43, 'zh-Hans')).toBeUndefined();
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd backend && npx vitest run test/cache-store.test.ts
```

Expected: FAIL，模块不存在。

- [ ] **Step 3: 写实现（hash 公式与旧 storage.ts 完全一致）**

```ts
// backend/lib/cache-store.ts
import { createHash } from 'node:crypto';
import { db } from './db';

// ---- 内存回退（dev/test）----
const memTranslations = new Map<string, string>();
const memSummaries = new Map<string, string>();

function digest(parts: string[]): string {
  const hash = createHash('sha256');
  for (const part of parts) hash.update(part).update('\0');
  return hash.digest('hex');
}

function translationKey(text: string, targetLanguage: string): string {
  const version = process.env.TRANSLATION_CACHE_VERSION?.trim() || 'v1';
  const model = process.env.MODEL_NAME?.trim() || 'unknown-model';
  return digest([version, model, targetLanguage, text]);
}

function summaryKey(storyId: number, targetLanguage: string): string {
  const version = process.env.TRANSLATION_CACHE_VERSION?.trim() || 'v1';
  const model = process.env.MODEL_NAME?.trim() || 'unknown-model';
  return digest([version, model, targetLanguage, String(storyId)]);
}

export async function getCachedTranslation(
  text: string,
  targetLanguage: string,
): Promise<string | undefined> {
  const hash = translationKey(text, targetLanguage);
  const client = await db();
  if (!client) return memTranslations.get(hash);
  const row = await client.translation.findUnique({ where: { hash } });
  return row?.result.trim() || undefined;
}

export async function cacheTranslation(
  text: string,
  targetLanguage: string,
  translation: string,
): Promise<void> {
  const value = translation.trim();
  if (!value) return;
  const hash = translationKey(text, targetLanguage);
  const client = await db();
  if (!client) {
    memTranslations.set(hash, value);
    return;
  }
  // 永久保存：同 hash 只写一次，冲突时保留旧值即可（幂等）
  await client.translation.upsert({
    where: { hash },
    create: { hash, lang: targetLanguage, source: text, result: value },
    update: { result: value },
  });
}

export async function getCachedSummary(
  storyId: number,
  targetLanguage: string,
): Promise<string | undefined> {
  const hash = summaryKey(storyId, targetLanguage);
  const client = await db();
  if (!client) return memSummaries.get(hash);
  const row = await client.summary.findUnique({ where: { hash } });
  return row?.result.trim() || undefined;
}

export async function cacheSummary(
  storyId: number,
  targetLanguage: string,
  summary: string,
): Promise<void> {
  const value = summary.trim();
  if (!value) return;
  const hash = summaryKey(storyId, targetLanguage);
  const client = await db();
  if (!client) {
    memSummaries.set(hash, value);
    return;
  }
  await client.summary.upsert({
    where: { hash },
    create: { hash, storyId, lang: targetLanguage, result: value },
    update: { result: value },
  });
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd backend && npx vitest run test/cache-store.test.ts
```

Expected: 4 passed。

- [ ] **Step 5: 提交**

```bash
git add backend/lib/cache-store.ts backend/test/cache-store.test.ts
git commit -m "feat(db): cache-store——翻译/摘要永久落库（hash 与旧 Redis key 同构）+ 内存回退"
```

---

### Task 5: lib/quota-store.ts — 配额原子计数

**Files:**
- Create: `backend/lib/quota-store.ts`
- Test: `backend/test/quota-store.test.ts`

- [ ] **Step 1: 写失败测试（从旧 storage.test.ts 移植配额部分）**

```ts
// backend/test/quota-store.test.ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('quota-store (in-memory)', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.DATABASE_URL;
    delete process.env.NODE_ENV;
  });

  it('reserves quota up to a limit then denies, with rollback', async () => {
    const { reserveTranslation } = await import('../lib/quota-store.js');
    const day = '2026-08-18';
    const a = await reserveTranslation(day, 'client-a', 2);
    expect(a.allowed).toBe(true);
    expect(a.remaining).toBe(1);
    const b = await reserveTranslation(day, 'client-a', 2);
    expect(b.allowed).toBe(true);
    expect(b.remaining).toBe(0);
    const c = await reserveTranslation(day, 'client-a', 2);
    expect(c.allowed).toBe(false);
    // 回滚 b 后可再预留一次
    await b.rollback();
    const d = await reserveTranslation(day, 'client-a', 2);
    expect(d.allowed).toBe(true);
  });

  it('clients are isolated', async () => {
    const { reserveTranslation } = await import('../lib/quota-store.js');
    const day = '2026-08-18';
    await reserveTranslation(day, 'client-a', 1);
    const other = await reserveTranslation(day, 'client-b', 1);
    expect(other.allowed).toBe(true);
  });

  it('peekTranslation reads current usage', async () => {
    const { reserveTranslation, peekTranslation } = await import('../lib/quota-store.js');
    const day = '2026-08-18';
    await reserveTranslation(day, 'client-c', 5);
    await reserveTranslation(day, 'client-c', 5);
    expect(await peekTranslation(day, 'client-c')).toBe(2);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd backend && npx vitest run test/quota-store.test.ts
```

Expected: FAIL，模块不存在。

- [ ] **Step 3: 写实现（PG 路径用 upsert 原子计数，越过上限即回减）**

```ts
// backend/lib/quota-store.ts
import { db } from './db';

export type Reservation = {
  allowed: boolean;
  remaining: number;
  rollback: () => Promise<void>;
};

// ---- 内存回退（dev/test）----
const memUsage = new Map<string, number>();

export async function reserveTranslation(
  day: string,
  clientId: string,
  limit: number,
): Promise<Reservation> {
  const key = `${day}:${clientId}`;
  const client = await db();
  if (!client) {
    const used = memUsage.get(key) ?? 0;
    if (used >= limit) return { allowed: false, remaining: 0, rollback: async () => undefined };
    memUsage.set(key, used + 1);
    return {
      allowed: true,
      remaining: limit - used - 1,
      rollback: async () => {
        const current = memUsage.get(key) ?? 1;
        if (current <= 1) memUsage.delete(key);
        else memUsage.set(key, current - 1);
      },
    };
  }

  // upsert 原子自增；超出上限立即回减并拒绝（并发安全：单行 UPDATE 原子）
  const row = await client.quotaUsage.upsert({
    where: { day_clientId: { day, clientId } },
    create: { day, clientId, used: 1 },
    update: { used: { increment: 1 } },
  });
  if (row.used > limit) {
    await client.quotaUsage.update({
      where: { day_clientId: { day, clientId } },
      data: { used: { decrement: 1 } },
    });
    return { allowed: false, remaining: 0, rollback: async () => undefined };
  }
  return {
    allowed: true,
    remaining: Math.max(0, limit - row.used),
    rollback: async () => {
      await client.quotaUsage.update({
        where: { day_clientId: { day, clientId } },
        data: { used: { decrement: 1 } },
      }).catch(() => undefined);
    },
  };
}

export async function peekTranslation(day: string, clientId: string): Promise<number> {
  const client = await db();
  if (!client) return memUsage.get(`${day}:${clientId}`) ?? 0;
  const row = await client.quotaUsage.findUnique({
    where: { day_clientId: { day, clientId } },
  });
  return row?.used ?? 0;
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd backend && npx vitest run test/quota-store.test.ts
```

Expected: 3 passed。

- [ ] **Step 5: 提交**

```bash
git add backend/lib/quota-store.ts backend/test/quota-store.test.ts
git commit -m "feat(db): quota-store——配额 upsert 原子计数 + rollback + 内存回退"
```

---

### Task 6: 路由切换到新 store + report-store

**Files:**
- Create: `backend/lib/report-store.ts`
- Modify: `backend/app/api/translate/route.ts:5`（import 行）
- Modify: `backend/app/api/translate/route.ts:57,63,70,74,75`（reserveDaily 保留，import 换）
- Modify: `backend/app/api/reader/summarize/route.ts:4`
- Modify: `backend/app/api/reader/quota/route.ts:4`
- Modify: `backend/app/api/reader/report/route.ts`（全文替换）
- Modify: `backend/test/routes/translate.test.ts:35`（import 路径）

- [ ] **Step 1: 写 report-store**

```ts
// backend/lib/report-store.ts
import { db } from './db';

export type ReportEntry = {
  storyId: number;
  commentId: number;
  reason: string;
  text: string;
  installId: string;
  ts: number;
};

// ---- 内存回退（dev/test）----
const memReports: ReportEntry[] = [];

export async function saveReport(entry: ReportEntry): Promise<void> {
  const client = await db();
  if (!client) {
    memReports.push(entry);
    return;
  }
  await client.report.create({
    data: {
      storyId: entry.storyId,
      commentId: entry.commentId,
      reason: entry.reason,
      text: entry.text,
      installId: entry.installId,
      ts: BigInt(entry.ts),
    },
  });
}
```

- [ ] **Step 2: 换 translate 路由 import**

`backend/app/api/translate/route.ts` 第 5 行：

```ts
// 旧
import { cacheTranslation, getCachedTranslation } from '../../../lib/storage';
// 新
import { cacheTranslation, getCachedTranslation } from '../../../lib/cache-store';
import { reserveDaily, today } from '../../../lib/quota';
```

`backend/lib/quota.ts` 中 `import { reserveTranslation } from './storage';` 改为 `from './quota-store'`（其余不动）。

- [ ] **Step 3: 换 summarize 路由 import**

`backend/app/api/reader/summarize/route.ts` 第 4 行：

```ts
import { cacheSummary, getCachedSummary } from '../../../../lib/cache-store';
```

- [ ] **Step 4: 换 quota 路由 import**

`backend/app/api/reader/quota/route.ts` 第 4 行：

```ts
import { peekTranslation } from '../../../../lib/quota-store';
```

- [ ] **Step 5: 重写 report 路由**

```ts
// backend/app/api/reader/report/route.ts（全文替换）
import { errorResponse, json } from '../../../../lib/http';
import { saveReport } from '../../../../lib/report-store';

const REASONS = new Set(['false_info', 'nsfw', 'spam', 'illegal', 'other']);

/**
 * POST /api/reader/report { storyId, commentId, reason, text? }
 *
 * 内容举报：接收 HN 评论的举报并落库（Postgres Report 表）。
 */
export async function POST(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0) {
    return errorResponse('invalid_request', 400);
  }

  let payload: unknown;
  try { payload = await request.json(); } catch { return errorResponse('invalid_request', 400); }

  const storyId = Number((payload as { storyId?: unknown }).storyId);
  const commentId = Number((payload as { commentId?: unknown }).commentId);
  const reason = String((payload as { reason?: unknown }).reason ?? '');
  if (!Number.isInteger(storyId) || !Number.isInteger(commentId) || !REASONS.has(reason)) {
    return errorResponse('invalid_request', 400);
  }
  const raw = (payload as { text?: unknown }).text;
  const text = typeof raw === 'string' ? raw.slice(0, 500) : '';

  try {
    await saveReport({ storyId, commentId, reason, text, installId, ts: Date.now() });
  } catch {
    // 落库失败不阻断用户反馈（旧版 Redis 失败同样静默）
  }
  return json({ ok: true });
}
```

- [ ] **Step 6: 更新 translate.test.ts 的 storage import**

`backend/test/routes/translate.test.ts` 第 35 行：

```ts
// 旧
const { cacheTranslation } = await import('../../lib/storage.js');
// 新
const { cacheTranslation } = await import('../../lib/cache-store.js');
```

- [ ] **Step 7: 跑全部路由测试**

```bash
cd backend && npx vitest run test/routes
```

Expected: 全部 pass（translate/quota/report/stories/items/tree 语义不变；`delete process.env.REDIS_URL` 留着无害）。

- [ ] **Step 8: 提交**

```bash
git add backend/lib/report-store.ts backend/lib/quota.ts backend/app backend/test/routes/translate.test.ts
git commit -m "refactor(api): translate/summarize/quota/report 切换 PG store"
```

---

### Task 7: hacker-news.ts 重写为 PG-first

**Files:**
- Modify: `backend/lib/hacker-news.ts`（全文替换，对外签名 fetchStoryIds/fetchItems 不变）
- Modify: `backend/test/hacker-news.test.ts`（最后一个用例改用 __testBackdateItem）

- [ ] **Step 1: 更新测试（旧文件 4 个用例中前 3 个不动，最后 1 个替换）**

```ts
// backend/test/hacker-news.test.ts 中替换 'serves cached items on upstream failure (stale)' 用例：
it('serves stored items on upstream failure (stale)', async () => {
  mockFetch({ '/item/9.json': { id: 9, title: 'cached' } });
  const { fetchItems } = await import('../lib/hacker-news.js');
  const { __testBackdateItem } = await import('../lib/hn-store.js');
  const first = await fetchItems([9]);
  expect(first.items[0]).toEqual({ id: 9, title: 'cached' });
  // fetchedAt 回拨 2 小时 → 超过 item fresh 窗口，必须重试上游
  await __testBackdateItem(9, 120);
  mockFetch({});
  const second = await fetchItems([9]);
  expect(second.items[0]).toEqual({ id: 9, title: 'cached' });
  expect(second.stale).toBe(true);
});
```

同时该文件 beforeEach 已有 `delete process.env.REDIS_URL`，追加 `delete process.env.DATABASE_URL; delete process.env.NODE_ENV;`。

- [ ] **Step 2: 跑测试确认失败（旧实现还依赖 storage.ts）**

```bash
cd backend && npx vitest run test/hacker-news.test.ts
```

Expected: FAIL（`__testBackdateItem` 不影响旧实现路径；旧 `setJsonCache` 已删的用例报错）。

- [ ] **Step 3: 写实现（全文替换 lib/hacker-news.ts）**

```ts
// backend/lib/hacker-news.ts
import './proxy';
import { readItems, readStoryList, saveStoryList, upsertItems } from './hn-store';

const defaultBaseUrl = 'https://hacker-news.firebaseio.com/v0';
const listFreshSeconds = 180;      // 列表 fresh 3min
const listStaleSeconds = 1200;     // 超 20min 同步刷新一次
const itemFreshSeconds = 900;      // 条目 fresh 15min
const fetchTimeoutMs = 8_000;
const fetchConcurrency = 20;

export type HackerNewsItem = Record<string, unknown>;

function baseUrl(): string {
  return (process.env.HACKER_NEWS_API_URL?.trim() || defaultBaseUrl).replace(/\/$/, '');
}

/** 上游拉取：配置源优先，失败回退直连 Firebase。 */
export async function fetchJson<T>(path: string): Promise<T> {
  const candidates = [...new Set([baseUrl(), defaultBaseUrl])];
  let lastError: Error = new Error('hacker_news_unavailable');
  for (const base of candidates) {
    try {
      const response = await fetch(`${base}${path}`, {
        signal: AbortSignal.timeout(fetchTimeoutMs),
        headers: { accept: 'application/json' },
      });
      if (!response.ok) throw new Error(`hacker_news_http_${response.status}`);
      return await response.json() as T;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error('hacker_news_unavailable');
      console.warn(`[geekread] HN fetch failed via ${base}: ${lastError.message}`);
    }
  }
  throw lastError;
}

function isValidItem(value: unknown): value is HackerNewsItem | null {
  if (value === null) return true;
  return typeof value === 'object' && !Array.isArray(value);
}

export async function fetchStoryIds(type: 'top' | 'latest'): Promise<{
  ids: number[];
  cached: boolean;
  stale: boolean;
}> {
  const stored = await readStoryList(type);
  const ageSeconds = stored ? (Date.now() - stored.fetchedAt.getTime()) / 1000 : Infinity;

  // fresh：直接返回，不碰上游
  if (stored && ageSeconds <= listFreshSeconds) {
    return { ids: stored.ids, cached: true, stale: false };
  }
  // stale 窗口内：返回旧值 + 后台刷新
  if (stored && ageSeconds <= listStaleSeconds) {
    refreshStoryListInBackground(type).catch(() => {});
    return { ids: stored.ids, cached: true, stale: true };
  }
  // 无数据或超 stale：同步刷新一次，失败时有旧值返旧值
  try {
    const path = type === 'top' ? '/topstories.json' : '/newstories.json';
    const ids = await fetchJson<number[]>(path);
    if (!Array.isArray(ids) || ids.some((id) => !Number.isInteger(id))) {
      throw new Error('hacker_news_invalid_response');
    }
    await saveStoryList(type, ids);
    return { ids, cached: false, stale: false };
  } catch (error) {
    if (stored) return { ids: stored.ids, cached: true, stale: true };
    throw error;
  }
}

async function refreshStoryListInBackground(type: 'top' | 'latest'): Promise<void> {
  try {
    const path = type === 'top' ? '/topstories.json' : '/newstories.json';
    const ids = await fetchJson<number[]>(path);
    if (Array.isArray(ids) && ids.every((id) => Number.isInteger(id))) {
      await saveStoryList(type, ids);
    }
  } catch {
    // 后台刷新失败不影响用户（下次请求再用 stale）
  }
}

type ItemOutcome = { item: HackerNewsItem | null; cached: boolean; stale: boolean };

async function resolveItem(id: number): Promise<ItemOutcome> {
  const rows = await readItems([id]);
  const hit = rows.get(id);
  if (hit) {
    const ageSeconds = (Date.now() - hit.fetchedAt.getTime()) / 1000;
    if (ageSeconds <= itemFreshSeconds) return { item: hit.raw, cached: true, stale: false };
    // 超 fresh：返回旧值 + 后台刷新（fire-and-forget）
    refreshItemInBackground(id).catch(() => {});
    return { item: hit.raw, cached: true, stale: true };
  }
  // 未落库（长尾）：回源一次并 upsert，此后永久本地
  try {
    const item = await fetchJson<unknown>(`/item/${id}.json`);
    if (!isValidItem(item)) throw new Error('hacker_news_invalid_response');
    await upsertItems([{ id, raw: item }]);
    return { item, cached: false, stale: false };
  } catch (error) {
    throw error;
  }
}

async function refreshItemInBackground(id: number): Promise<void> {
  try {
    const item = await fetchJson<unknown>(`/item/${id}.json`);
    if (isValidItem(item)) await upsertItems([{ id, raw: item }]);
  } catch {
    // 失败保留旧值
  }
}

export async function fetchItems(ids: number[]): Promise<{
  items: Array<HackerNewsItem | null>;
  cached: boolean;
  stale: boolean;
}> {
  const uniqueIds = [...new Set(ids)];
  const results = new Map<number, ItemOutcome>();
  let nextIndex = 0;

  async function worker(): Promise<void> {
    while (nextIndex < uniqueIds.length) {
      const index = nextIndex++;
      const id = uniqueIds[index];
      if (id === undefined) return;
      results.set(id, await resolveItem(id));
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(fetchConcurrency, uniqueIds.length) }, () => worker()),
  );
  const ordered = ids.map((id) => results.get(id));
  return {
    items: ordered.map((result) => result?.item ?? null),
    cached: ordered.every((result) => result?.cached),
    stale: ordered.some((result) => result?.stale),
  };
}
```

注意：`fetchItems` 旧语义里"上游失败但有缓存 → 返回 stale"现在拆为：fresh 内直接命中；超 fresh 返回旧值（stale=true）+ 后台刷新，**读路径永不因上游失败而丢已有数据**。未落库且回源失败 → resolveItem throw → fetchItems 整体 reject（与旧行为一致，tree/items 路由 catch 后 503）。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd backend && npx vitest run test/hacker-news.test.ts test/routes/tree.test.ts test/routes/items.test.ts test/routes/stories.test.ts
```

Expected: 全部 pass（对外签名与返回语义不变）。

- [ ] **Step 5: 提交**

```bash
git add backend/lib/hacker-news.ts backend/test/hacker-news.test.ts
git commit -m "feat(hn): hacker-news 重写 PG-first——SWR + 长尾回源一次落库"
```

---

### Task 8: lib/hn-health.ts — AIMD 状态机

**Files:**
- Create: `backend/lib/hn-health.ts`
- Test: `backend/test/hn-health.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
// backend/test/hn-health.test.ts
import { beforeEach, describe, expect, it } from 'vitest';

describe('hn-health (AIMD)', () => {
  beforeEach(async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    hnHealth.reset();
  });

  it('level 0：60s 间隔、树预算 5', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    expect(hnHealth.intervalMs()).toBe(60_000);
    expect(hnHealth.treeBudget()).toBe(5);
  });

  it('429 立即降一级；恢复需连续 10 个干净 tick', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    hnHealth.noteRequest(false, { status: 429 });
    expect(hnHealth.intervalMs()).toBe(120_000);
    expect(hnHealth.treeBudget()).toBe(2);

    for (let i = 0; i < 9; i++) hnHealth.noteTickClean();
    expect(hnHealth.intervalMs()).toBe(120_000); // 9 次还不够
    hnHealth.noteTickClean();
    expect(hnHealth.intervalMs()).toBe(60_000);  // 第 10 次恢复
  });

  it('错误率 >30%（窗口 100）触发降级', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    for (let i = 0; i < 69; i++) hnHealth.noteRequest(true);
    for (let i = 0; i < 31; i++) hnHealth.noteRequest(false);
    expect(hnHealth.currentLevel()).toBe(1); // 31% > 30%
  });

  it('连续降级封顶 600s；Retry-After 直接遵守', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    hnHealth.noteRequest(false, { status: 429, retryAfterSeconds: 45 });
    for (let i = 0; i < 12; i++) hnHealth.noteTickClean(); // 清干净再连降
    hnHealth.noteRequest(false, { status: 429 });
    hnHealth.noteRequest(false, { status: 429 });
    hnHealth.noteRequest(false, { status: 429 });
    expect(hnHealth.intervalMs()).toBe(600_000);
    expect(hnHealth.treeBudget()).toBe(0);
  });

  it('正常请求不改变 level', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    for (let i = 0; i < 100; i++) hnHealth.noteRequest(true);
    expect(hnHealth.currentLevel()).toBe(0);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd backend && npx vitest run test/hn-health.test.ts
```

Expected: FAIL，模块不存在。

- [ ] **Step 3: 写实现**

```ts
// backend/lib/hn-health.ts

/**
 * HN 上游健康状态机（AIMD）：
 * - 降级（乘性）：429/Retry-After 立即；窗口错误率 >30% 在 tick 边界降
 * - 恢复（加性）：连续 10 个无错误 tick 才降一级
 * - 级别 0~3 → 间隔 [60,120,300,600]s，树预算 [5,2,0,0]
 * 进程内存态，不持久化；重启从 level 0 重新探测。
 */
const INTERVALS_MS = [60_000, 120_000, 300_000, 600_000] as const;
/** level 0 树预算由 env WARM_TREE_BUDGET 控制（默认 5），降级梯 2→0 固定 */
const BASE_TREE_BUDGET = Number(process.env.WARM_TREE_BUDGET ?? 5);
const TREE_BUDGETS = [BASE_TREE_BUDGET, 2, 0, 0];
const WINDOW = 100;
const ERROR_RATE_LIMIT = 0.3;
const CLEAN_TICKS_TO_RECOVER = 10;

export type RequestOutcome = { status?: number; retryAfterSeconds?: number };

class HnHealth {
  private level = 0;
  private window: boolean[] = [];
  private cleanTicks = 0;
  private retryUntil = 0;

  reset(): void {
    this.level = 0;
    this.window = [];
    this.cleanTicks = 0;
    this.retryUntil = 0;
  }

  /** 每个 HN 请求后调用（读路径 + 调度器都记）。 */
  noteRequest(ok: boolean, outcome: RequestOutcome = {}): void {
    const limited = outcome.status === 429;
    this.window.push(ok);
    if (this.window.length > WINDOW) this.window.shift();
    if (limited || outcome.retryAfterSeconds !== undefined) {
      this.degrade();
      if (outcome.retryAfterSeconds !== undefined) {
        this.retryUntil = Math.max(this.retryUntil, Date.now() + outcome.retryAfterSeconds * 1000);
      }
    }
  }

  /** 每个 tick 结束且本 tick 无错误时调用。 */
  noteTickClean(): void {
    this.cleanTicks += 1;
    if (this.cleanTicks >= CLEAN_TICKS_TO_RECOVER && this.level > 0) {
      this.level -= 1;
      this.cleanTicks = 0;
    }
  }

  /** tick 开始时调用：窗口错误率超阈值 → 降一级并清零干净计数。 */
  noteTickStart(): void {
    const errors = this.window.filter((ok) => !ok).length;
    if (this.window.length > 0 && errors / this.window.length > ERROR_RATE_LIMIT) {
      this.degrade();
    }
  }

  private degrade(): void {
    if (this.level < INTERVALS_MS.length - 1) this.level += 1;
    this.cleanTicks = 0;
  }

  currentLevel(): number {
    return this.level;
  }

  intervalMs(): number {
    if (Date.now() < this.retryUntil) {
      // Retry-After 生效期内：取 max(当前级别间隔, 剩余等待)
      return Math.max(INTERVALS_MS[this.level], this.retryUntil - Date.now());
    }
    return INTERVALS_MS[this.level];
  }

  treeBudget(): number {
    return TREE_BUDGETS[this.level];
  }
}

export const hnHealth = new HnHealth();
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd backend && npx vitest run test/hn-health.test.ts
```

Expected: 5 passed。

- [ ] **Step 5: 把健康记录接入 fetchJson（Task 7 的 hacker-news.ts）**

`backend/lib/hacker-news.ts` 顶部加：

```ts
import { hnHealth } from './hn-health';
```

`fetchJson` 的两个分支改为记录结果（成功/失败/429/Retry-After）：

```ts
export async function fetchJson<T>(path: string): Promise<T> {
  const candidates = [...new Set([baseUrl(), defaultBaseUrl])];
  let lastError: Error = new Error('hacker_news_unavailable');
  for (const base of candidates) {
    try {
      const response = await fetch(`${base}${path}`, {
        signal: AbortSignal.timeout(fetchTimeoutMs),
        headers: { accept: 'application/json' },
      });
      if (!response.ok) {
        const retryAfter = Number(response.headers.get('retry-after'));
        hnHealth.noteRequest(false, {
          status: response.status,
          retryAfterSeconds: Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter : undefined,
        });
        throw new Error(`hacker_news_http_${response.status}`);
      }
      hnHealth.noteRequest(true);
      return await response.json() as T;
    } catch (error) {
      if (!(error instanceof Error) || !error.message.startsWith('hacker_news_http_')) {
        hnHealth.noteRequest(false); // 超时/网络错误
      }
      lastError = error instanceof Error ? error : new Error('hacker_news_unavailable');
      console.warn(`[geekread] HN fetch failed via ${base}: ${lastError.message}`);
    }
  }
  throw lastError;
}
```

- [ ] **Step 6: 回归测试**

```bash
cd backend && npx vitest run test/hacker-news.test.ts test/hn-health.test.ts
```

Expected: 全部 pass。

- [ ] **Step 7: 提交**

```bash
git add backend/lib/hn-health.ts backend/test/hn-health.test.ts backend/lib/hacker-news.ts
git commit -m "feat(sync): hn-health AIMD 状态机 + fetchJson 健康埋点"
```

---

### Task 9: lib/sync.ts — 预热 tick

**Files:**
- Create: `backend/lib/sync.ts`
- Test: `backend/test/sync.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
// backend/test/sync.test.ts
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function mockFetch(map: Record<string, unknown>) {
  const spy = vi.fn(async (url: string | URL | Request) => {
    const path = String(typeof url === 'string' ? url : url.toString());
    const entry = Object.entries(map).find(([key]) => path.endsWith(key));
    if (!entry) return new Response('not found', { status: 502 });
    return new Response(JSON.stringify(entry[1]), {
      status: 200, headers: { 'content-type': 'application/json' },
    });
  });
  globalThis.fetch = spy as unknown as typeof fetch;
  return spy;
}

describe('sync tick', () => {
  beforeEach(async () => {
    vi.resetModules();
    delete process.env.DATABASE_URL;
    delete process.env.NODE_ENV;
    delete process.env.HACKER_NEWS_API_URL;
    const { hnHealth } = await import('../lib/hn-health.js');
    hnHealth.reset();
  });
  afterEach(() => vi.restoreAllMocks());

  it('warmLists 拉列表并保存', async () => {
    const spy = mockFetch({
      '/topstories.json': [1, 2],
      '/newstories.json': [3],
    });
    const { warmLists } = await import('../lib/sync.js');
    const { readStoryList } = await import('../lib/hn-store.js');
    const r = await warmLists();
    expect(r).toEqual({ top: 2, latest: 1 });
    expect((await readStoryList('top'))?.ids).toEqual([1, 2]);
    expect(spy).toHaveBeenCalledTimes(2);
  });

  it('warmStoryHeaders upsert 文章头并返回 descendants 增长的 id 集合', async () => {
    const { upsertItems } = await import('../lib/hn-store.js');
    await upsertItems([{ id: 1, raw: { id: 1, type: 'story', descendants: 5 } }]);
    const spy = mockFetch({
      '/item/1.json': { id: 1, type: 'story', descendants: 9 },
      '/item/2.json': { id: 2, type: 'story', descendants: 0 },
    });
    const { warmStoryHeaders } = await import('../lib/sync.js');
    const grown = await warmStoryHeaders([1, 2]);
    expect(grown).toEqual([1]); // 1 的 descendants 5→9 增长；2 是新入库不算增长
    const { readItems } = await import('../lib/hn-store.js');
    expect((await readItems([1])).get(1)?.raw).toMatchObject({ descendants: 9 });
    expect(spy).toHaveBeenCalledTimes(2);
  });

  it('warmTrees 受预算约束，只拉增长树的评论', async () => {
    // story 1（descendants 增长，kids=[10]），评论 10 已在库且 fresh → 不再拉
    const { upsertItems } = await import('../lib/hn-store.js');
    await upsertItems([{ id: 1, raw: { id: 1, type: 'story', descendants: 5, kids: [10] } }]);
    await upsertItems([{ id: 10, raw: { id: 10, type: 'comment', text: 'c' } }]);
    mockFetch({
      '/item/1.json': { id: 1, type: 'story', descendants: 8, kids: [10] },
      '/item/10.json': { id: 10, type: 'comment', text: 'c2' },
    });
    const { warmTrees } = await import('../lib/sync.js');
    const n = await warmTrees([1], 5);
    expect(n).toBe(1);
    const { readItems } = await import('../lib/hn-store.js');
    // 评论 10 fresh（刚 upsert），fetchItems 不会回源它 → spy 未被调用拉 /item/10
  });

  it('tick 串联三层并尊重预算', async () => {
    const { upsertItems, saveStoryList } = await import('../lib/hn-store.js');
    await saveStoryList('top', [1]);
    await upsertItems([{ id: 1, raw: { id: 1, type: 'story', descendants: 5, kids: [] } }]);
    mockFetch({
      '/topstories.json': [1],
      '/newstories.json': [],
      '/item/1.json': { id: 1, type: 'story', descendants: 7, kids: [] },
    });
    const { tick } = await import('../lib/sync.js');
    const r = await tick();
    expect(r).toMatchObject({ lists: { top: 1, latest: 0 }, trees: 1 });
  });

  it('上游全挂时 tick 不抛（降级语义，下个 tick 再试）', async () => {
    mockFetch({});
    const { tick } = await import('../lib/sync.js');
    const r = await tick();
    expect(r.errors).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd backend && npx vitest run test/sync.test.ts
```

Expected: FAIL，模块不存在。

- [ ] **Step 3: 写实现**

```ts
// backend/lib/sync.ts
import { fetchItems, fetchJson } from './hacker-news';
import { oldestFetchedStories, readItems, readStoryList, saveStoryList, upsertItems } from './hn-store';
import { hnHealth } from './hn-health';

const TOP_N = Number(process.env.WARM_TOP_N ?? 50);
const LATEST_N = Number(process.env.WARM_LATEST_N ?? 50);
const TREE_N = Number(process.env.WARM_TREE_N ?? 30);
/** 轮转补刷的最小树龄（分钟）：刚刷过的树不重复进入轮转 */
const TREE_ROTATE_MIN_AGE_MINUTES = 30;

export type TickResult = {
  lists: { top: number; latest: number };
  headers: number;
  trees: number;
  errors: number;
};

/** 列表层：拉 top/latest 列表并保存。 */
export async function warmLists(): Promise<{ top: number; latest: number }> {
  const [top, latest] = await Promise.all([
    fetchJson<number[]>('/topstories.json'),
    fetchJson<number[]>('/newstories.json'),
  ]);
  await saveStoryList('top', top.slice(0, TOP_N));
  await saveStoryList('latest', latest.slice(0, LATEST_N));
  return { top: Math.min(top.length, TOP_N), latest: Math.min(latest.length, LATEST_N) };
}

/**
 * 文章头层：拉列表头部文章本体并 upsert。
 * 返回 descendants 增长了的文章 id（树层增量触发依据）。
 */
export async function warmStoryHeaders(ids: number[]): Promise<number[]> {
  if (ids.length === 0) return [];
  const before = await readItems(ids);
  const grown: number[] = [];
  const res = await fetchItems(ids);
  for (let i = 0; i < ids.length; i++) {
    const old = before.get(ids[i]!);
    const fresh = res.items[i];
    const oldDesc = typeof (old?.raw as { descendants?: unknown })?.descendants === 'number'
      ? (old!.raw as { descendants: number }).descendants : undefined;
    const newDesc = typeof (fresh as { descendants?: unknown } | null)?.descendants === 'number'
      ? (fresh as { descendants: number }).descendants : undefined;
    if (oldDesc !== undefined && newDesc !== undefined && newDesc > oldDesc) grown.push(ids[i]!);
  }
  return grown;
}

/**
 * 评论树层：候选 = descendants 增长的树 + 轮转最老树；每 tick 预算上限。
 * 树内条目走 fetchItems（fresh 的自动跳过上游，天然增量）。
 */
export async function warmTrees(grown: number[], budget: number): Promise<number> {
  if (budget <= 0) return 0;
  const rotated = await oldestFetchedStories(budget, TREE_ROTATE_MIN_AGE_MINUTES);
  const seen = new Set<number>();
  const candidates: number[] = [];
  for (const id of [...grown, ...rotated]) {
    if (!seen.has(id)) { seen.add(id); candidates.push(id); }
  }
  let synced = 0;
  for (const storyId of candidates.slice(0, budget)) {
    try {
      // 复用 tree 语义：BFS 拉整树（fetchItems 对 fresh 条目直接命中本地）
      const storyRows = await readItems([storyId]);
      const story = storyRows.get(storyId)?.raw as { kids?: unknown } | null | undefined;
      const frontier: number[] = Array.isArray(story?.kids)
        ? (story!.kids as unknown[]).filter((k): k is number => typeof k === 'number')
        : [];
      const all: number[] = [];
      const seenIds = new Set<number>([storyId]);
      while (frontier.length > 0 && all.length < 200) {
        const batch = frontier.splice(0, 50);
        const res = await fetchItems(batch);
        for (const item of res.items) {
          if (item === null) continue;
          const id = Number(item.id);
          if (!id || seenIds.has(id)) continue;
          seenIds.add(id);
          all.push(id);
          const kids = Array.isArray(item.kids)
            ? item.kids.filter((k): k is number => typeof k === 'number') : [];
          for (const k of kids) if (all.length < 200) frontier.push(k);
        }
      }
      // 树根 upsert 已由 warmStoryHeaders/fetchItems 完成；确认 story 本体 fetchedAt 已刷新
      const rows = await readItems([storyId]);
      if (!rows.has(storyId)) await upsertItems([{ id: storyId, raw: story ?? null }]);
      synced += 1;
    } catch {
      // 单棵树失败不影响其他树
    }
  }
  return synced;
}

/** 调度器每 tick 入口。 */
export async function tick(): Promise<TickResult> {
  hnHealth.noteTickStart();
  let errors = 0;
  let lists = { top: 0, latest: 0 };
  try {
    lists = await warmLists();
  } catch { errors += 1; }

  const top = await readStoryList('top');
  const latest = await readStoryList('latest');
  const headerIds = [...new Set([...(top?.ids.slice(0, TREE_N) ?? []), ...(latest?.ids.slice(0, TREE_N) ?? [])])];
  let grown: number[] = [];
  try {
    grown = await warmStoryHeaders(headerIds);
  } catch { errors += 1; }

  let trees = 0;
  try {
    trees = await warmTrees(grown, hnHealth.treeBudget());
  } catch { errors += 1; }

  if (errors === 0) hnHealth.noteTickClean();
  return { lists, headers: headerIds.length, trees, errors };
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd backend && npx vitest run test/sync.test.ts
```

Expected: 5 passed。

- [ ] **Step 5: 提交**

```bash
git add backend/lib/sync.ts backend/test/sync.test.ts
git commit -m "feat(sync): 预热 tick——列表/文章头/评论树三层增量 + AIMD 预算"
```

---

### Task 10: scheduler + instrumentation

**Files:**
- Create: `backend/lib/scheduler.ts`
- Create: `backend/instrumentation.ts`

无单测（纯启动接线，部署 smoke 覆盖）。

- [ ] **Step 1: 写 scheduler（自调度循环，间隔随 AIMD 变化）**

```ts
// backend/lib/scheduler.ts
import { tick } from './sync';
import { hnHealth } from './hn-health';

/**
 * 自调度循环：间隔 = hnHealth.intervalMs()（AIMD 自适应）。
 * 用 setTimeout 链而非 setInterval，间隔才能动态变化。
 */
export function startScheduler(): void {
  const run = async (): Promise<void> => {
    try {
      const result = await tick();
      process.stdout.write(`[geekread][sync] tick: ${JSON.stringify(result)}\n`);
    } catch (error) {
      process.stderr.write(`[geekread][sync] tick crashed: ${String(error)}\n`);
    }
    setTimeout(run, hnHealth.intervalMs()).unref();
  };
  // 启动延迟 10s 错峰（避开服务刚起时的流量高峰）
  setTimeout(run, 10_000).unref();
}
```

- [ ] **Step 2: 写 instrumentation（Next 启动钩子）**

```ts
// backend/instrumentation.ts
/**
 * Next.js 启动钩子：生产环境拉起 HN 预热调度器（60s 级，AIMD 自适应）。
 * dev 不自动起（手动打 /api/reader/warm 验证）。
 */
export async function register(): Promise<void> {
  if (process.env.NEXT_RUNTIME !== 'nodejs') return;
  if (process.env.NODE_ENV !== 'production') return;
  const { startScheduler } = await import('./lib/scheduler');
  startScheduler();
}
```

- [ ] **Step 3: 类型检查 + 全量测试**

```bash
cd backend && npx tsc --noEmit && npx vitest run
```

Expected: 类型无错；测试全部 pass。

- [ ] **Step 4: 提交**

```bash
git add backend/lib/scheduler.ts backend/instrumentation.ts
git commit -m "feat(sync): 进程内置调度器（instrumentation 拉起，间隔随 AIMD）"
```

---

### Task 11: warm 路由重写

**Files:**
- Modify: `backend/app/api/reader/warm/route.ts`（全文替换）

- [ ] **Step 1: 重写（复用 sync 层，手动 warm 允许更大预算）**

```ts
// backend/app/api/reader/warm/route.ts（全文替换）
import { errorResponse, json } from '../../../../lib/http';
import { readStoryList } from '../../../../lib/hn-store';
import { tick, warmLists, warmStoryHeaders, warmTrees } from '../../../../lib/sync';

/**
 * 缓存预热（手动触发）：列表 + 文章头 + 评论树全量一轮。
 * 生产由内置调度器每分钟自动跑；此接口供运维手动触发/验证。
 * 需带 ?token= 校验，避免被外部滥用拉取 HN。
 */
export async function GET(request: Request): Promise<Response> {
  const token = new URL(request.url).searchParams.get('token');
  const expected = process.env.WARM_CACHE_TOKEN?.trim();
  if (expected && token !== expected) return errorResponse('forbidden', 403);

  try {
    // 手动触发走完整 tick（不受 AIMD 当前预算限制时可用 ?full=1 提高树预算）
    const full = new URL(request.url).searchParams.get('full') === '1';
    if (!full) {
      return json({ ok: true, ...(await tick()) });
    }
    const lists = await warmLists();
    const merged: number[] = [];
    const seen = new Set<number>();
    const tl = await readStoryList('top');
    const lt = await readStoryList('latest');
    for (const id of [...(tl?.ids ?? []), ...(lt?.ids ?? [])]) {
      if (!seen.has(id)) { seen.add(id); merged.push(id); }
    }
    const grown = await warmStoryHeaders(merged.slice(0, 30));
    const trees = await warmTrees(grown, 30);
    return json({ ok: true, lists, headers: Math.min(merged.length, 30), trees });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, 500);
  }
}
```

- [ ] **Step 2: 手动验证（本地起 dev 库）**

```bash
cd backend && DATABASE_URL=postgresql://postgres:dev@localhost:5433/postgres npm run dev &
sleep 5 && curl -s http://localhost:8787/api/reader/warm | head -c 300
```

Expected: `{"ok":true,...}` 带 lists/headers/trees 计数；PG 里 `select count(*) from "HnItem";` > 0。

- [ ] **Step 3: 提交**

```bash
git add backend/app/api/reader/warm/route.ts
git commit -m "feat(api): warm 路由复用 sync 层（支持 ?full=1 大预算）"
```

---

### Task 12: 删旧存储 + 部署配置 + 收尾

**Files:**
- Delete: `backend/lib/storage.ts`、`backend/test/storage.test.ts`、`backend/warm-cache.cjs`
- Modify: `backend/package.json`（确认无 redis 依赖）
- Modify: `backend/Dockerfile`
- Create: `backend/docker-compose.yml`
- Modify: `backend/.env.example`、`backend/README.md`

- [ ] **Step 1: 删旧文件（先全局确认无引用）**

```bash
cd backend && grep -rn "lib/storage\|warm-cache" app lib test --include="*.ts" ; echo "exit=$?"
```

Expected: 无输出（exit=1）。有引用则先处理再删。

```bash
git rm backend/lib/storage.ts backend/test/storage.test.ts backend/warm-cache.cjs
```

- [ ] **Step 2: 跑全量测试确认删除无碍**

```bash
cd backend && npx vitest run
```

Expected: 全部 pass（storage.test.ts 已删，其余不受影响）。

- [ ] **Step 3: 写 docker-compose.yml**

```yaml
# backend/docker-compose.yml
services:
  postgres:
    image: docker.m.daocloud.io/library/postgres:16-alpine
    environment:
      POSTGRES_USER: geekread
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD}
      POSTGRES_DB: geekread
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U geekread"]
      interval: 5s
      timeout: 3s
      retries: 12

  backend:
    build: .
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://geekread:${POSTGRES_PASSWORD}@postgres:5432/geekread
      MODEL_API_URL: ${MODEL_API_URL}
      MODEL_API_KEY: ${MODEL_API_KEY}
      MODEL_NAME: ${MODEL_NAME}
      ENTITLEMENT_SIGNING_SECRET: ${ENTITLEMENT_SIGNING_SECRET}
      HACKER_NEWS_API_URL: ${HACKER_NEWS_API_URL:-}
      WARM_CACHE_TOKEN: ${WARM_CACHE_TOKEN:-}
    ports:
      - "8787:8787"

volumes:
  pgdata:
```

- [ ] **Step 4: 改 Dockerfile（prisma generate + migrate deploy 入口）**

```dockerfile
# backend/Dockerfile（全文替换）
FROM docker.m.daocloud.io/library/node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci

FROM docker.m.daocloud.io/library/node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# schema 先于 next build 生成客户端类型
RUN npx prisma generate && npm run build

FROM docker.m.daocloud.io/library/node:22-alpine AS run
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev
COPY --from=build /app/.next ./.next
COPY --from=build /app/package.json ./package.json
COPY prisma ./prisma
COPY --from=build /app/node_modules/.prisma ./node_modules/.prisma
EXPOSE 8787
# 启动前执行迁移（幂等）；prisma CLI 已在 dependencies
CMD ["sh", "-c", "npx prisma migrate deploy && npm start"]
```

- [ ] **Step 5: 更新 .env.example**

```bash
# backend/.env.example 中：
# - 删除 REDIS_URL、TRANSLATION_CACHE_TTL_SECONDS 两行及注释
# - 加入：
# DATABASE_URL=postgresql://geekread:password@localhost:5432/geekread
# WARM_CACHE_TOKEN=
# WARM_TOP_N=50
# WARM_LATEST_N=50
# WARM_TREE_N=30
# WARM_TREE_BUDGET=5
```

- [ ] **Step 6: 更新 README（部署节）**

`backend/README.md` 快速开始改为：

```markdown
```bash
cp .env.example .env.local   # 至少填 DATABASE_URL、MODEL_API_URL/KEY/NAME 与 ENTITLEMENT_SIGNING_SECRET
docker compose up -d --build # postgres + backend（启动自动 prisma migrate deploy）
npm install
npm run dev                  # http://localhost:8787（内置调度器仅生产自动启用）
```

存储：PostgreSQL 唯一持久层（文章/评论/翻译/摘要/配额/举报）。
无 `DATABASE_URL` 时自动回退内存（仅 dev/test）。生产内置 60s 预热调度器（AIMD 自适应）。
```

- [ ] **Step 7: 全量回归**

```bash
cd backend && npx tsc --noEmit && npx vitest run && npm run build
```

Expected: 类型 0 错、测试全 pass、next build 成功。

- [ ] **Step 8: 部署 smoke（compose 起真栈）**

```bash
cd backend && POSTGRES_PASSWORD=devsmoke docker compose up -d --build
sleep 20
curl -s http://localhost:8787/api/reader/stories?type=top | head -c 120
docker compose exec postgres psql -U geekread -c 'select count(*) from "HnItem";'
docker compose logs backend --tail 20   # 应见 [geekread][sync] tick: {...}
```

Expected: stories 返回 id 列表；HnItem 行数 > 0；日志有 tick 输出。

- [ ] **Step 9: 提交**

```bash
git add -A backend
git commit -m "feat(deploy): 删 Redis/storage——compose 双容器 + migrate deploy 入口 + 环境变量清理"
```

---

## 验收清单（对照 spec §6/§8）

- [ ] `stories/items/tree/translate/summarize/quota/report` 全部 PG-first，签名未变（客户端零改动）
- [ ] 长尾未落库文章：首次打开回源 HN 一次并落库，第二次纯本地
- [ ] 翻译/摘要永久保存（无 TTL 字段即验证）
- [ ] 调度器 60s 起步、AIMD 四级退避、树预算 5/2/0/0
- [ ] Redis 相关代码/依赖/env 全部移除
- [ ] `npx vitest run` 全绿（无需数据库）
