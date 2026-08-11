# 极客译读 Foundation 实施计划（Plan 1：共享契约 + 专属 Next.js 后端）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建成极客译读专属 Next.js 后端（HN 代理 + 翻译 + 配额 + entitlement 验签）+ 跨端 API 契约，可独立运行/测试，为 RN 与 ArkTS 客户端提供统一入口。

**Architecture:** 从 Hacki-OH `backend/src/`（TS）移植核心逻辑（hacker-news / model / storage / entitlement / 批处理），把 AGC Callable 入口换成 Next.js App Router route handlers。Redis 可选（dev 用内存 Map 兜底），LLM 走 OpenAI 兼容接口（MaaS/DeepSeek/OpenAI 任选）。配额按 `x-install-id`（匿名）或 `Authorization: Bearer <entitlement>`（Pro）。

**Tech Stack:** Next.js 16 (App Router, API-only) · TypeScript 5.8 · vitest · redis(可选) · OpenAI 兼容 LLM。

**源参考（Hacki-OH，文件存在，移植时读取）：**
- `Hacki-OH/backend/src/hacker-news.ts`（fetchStoryIds / fetchItems，SWR 缓存）
- `Hacki-OH/backend/src/model.ts`（translateWithModel，OpenAI 兼容）
- `Hacki-OH/backend/src/storage.ts`（cache / SWR / quota / report，Redis+内存兜底）
- `Hacki-OH/backend/src/function.ts`（hasProEntitlement / 批处理 worker / 校验 helper）

**端点契约：**
| 方法 | 路径 | 入参 | 出参 |
|---|---|---|---|
| GET | `/api/reader/stories` | `?type=top\|latest` | `{ ids:number[], cached:boolean, stale:boolean }` |
| POST | `/api/reader/items` | `{ ids:number[] }` | `{ items:(Item\|null)[], cached, stale }` |
| POST | `/api/translate` | `{ entries:[{key,text}], targetLanguage }` + 头 `x-install-id` / `Authorization` | `{ results:[{key,translation?\|error,cached?}], remainingTranslations? }` |

> 评论树：客户端用 `/reader/items` 递归抓取（story.kids → items → 每项 kids → ...），与服务端无关。本计划不建 `/reader/comments`。

---

## 文件结构

```
geekread/backend/
├── package.json              新建
├── tsconfig.json             新建
├── next.config.mjs           新建
├── vitest.config.ts          新建
├── .env.example              新建
├── .gitignore                新建
├── app/
│   ├── layout.ts             新建（最小 root layout）
│   └── api/
│       ├── reader/stories/route.ts        新建（薄路由，调 lib）
│       ├── reader/items/route.ts          新建
│       └── translate/route.ts             新建
├── lib/
│   ├── env.ts                新建（env 访问 + 默认值）
│   ├── hacker-news.ts        移植（verbatim）
│   ├── model.ts              移植（verbatim，仅删华为注释措辞）
│   ├── storage.ts            移植（verbatim）
│   ├── entitlement.ts        新建（从 function.ts 抽 hasProEntitlement + signEntitlement）
│   ├── quota.ts              新建（limit 计算 + reserve 封装）
│   └── http.ts               新建（json/error 响应 + requireString/requireIds）
└── test/
    ├── env.test.ts
    ├── storage.test.ts
    ├── hacker-news.test.ts
    ├── model.test.ts
    ├── entitlement.test.ts
    ├── quota.test.ts
    └── routes/
        ├── stories.test.ts
        ├── items.test.ts
        └── translate.test.ts

geekread/shared/
├── api-schema.json           新建（所有请求/响应类型的 JSON Schema，单一真理源）
└── codegen/
    └── gen-types.mjs         新建（schema → shared/generated/types.ts）
```

每个 lib 文件单一职责；route 文件保持薄（校验 → 调 lib → 响应）；test 与源一一对应。

---

### Task 1: 后端脚手架

**Files:**
- Create: `geekread/backend/package.json`
- Create: `geekread/backend/tsconfig.json`
- Create: `geekread/backend/next.config.mjs`
- Create: `geekread/backend/vitest.config.ts`
- Create: `geekread/backend/.env.example`
- Create: `geekread/backend/.gitignore`
- Create: `geekread/backend/app/layout.ts`

- [ ] **Step 1: 建 `package.json`**

```json
{
  "name": "geekread-backend",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "next dev -p 8787",
    "build": "next build",
    "start": "next start -p 8787",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "next": "16.2.12",
    "react": "19.2.4",
    "react-dom": "19.2.4",
    "redis": "^6.1.0"
  },
  "devDependencies": {
    "@types/node": "^24.0.0",
    "@types/react": "^19.0.0",
    "typescript": "^5.8.0",
    "vitest": "^3.2.0"
  }
}
```

- [ ] **Step 2: 建 `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "allowJs": false,
    "noEmit": true,
    "types": ["node", "vitest/globals"]
  },
  "include": ["app", "lib", "test", "next-env.d.ts"]
}
```

- [ ] **Step 3: 建 `next.config.mjs`、`vitest.config.ts`、`.env.example`、`.gitignore`**

`next.config.mjs`:
```js
export default { reactStrictMode: true };
```

`vitest.config.ts`:
```ts
import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: { environment: 'node', globals: true, include: ['test/**/*.test.ts'] },
});
```

`.env.example`:
```bash
# LLM (OpenAI 兼容)
MODEL_API_URL=https://maas-api.cn-east-3.myhuaweicloud.com/v1/inferring/xxx/chat/completions
MODEL_API_KEY=replace-me
MODEL_NAME=DeepSeek-R1-671B
# 缓存（可选，缺省走内存）
REDIS_URL=
# 配额
FREE_DAILY_TRANSLATIONS=20
PRO_DAILY_TRANSLATIONS=500
# Pro 权益验签（与 MobileStarter server 共享密钥）
ENTITLEMENT_SIGNING_SECRET=replace-me
TRANSLATION_CACHE_TTL_SECONDS=2592000
TRANSLATION_CACHE_VERSION=v1
HACKER_NEWS_API_URL=https://hacker-news.firebaseio.com/v0
```

`.gitignore`:
```
node_modules/
.next/
.env
.env.local
*.log
```

- [ ] **Step 4: 建最小 `app/layout.ts`**

```ts
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return children;
}
```

- [ ] **Step 5: 安装依赖**

Run: `cd geekread/backend && npm install`
Expected: 安装成功，无错误。

- [ ] **Step 6: 提交**

```bash
cd geekread && git add backend && git commit -m "feat(backend): scaffold Next.js API-only backend"
```

---

### Task 2: `lib/env.ts` + 测试

**Files:**
- Create: `geekread/backend/lib/env.ts`
- Test: `geekread/backend/test/env.test.ts`

- [ ] **Step 1: 写失败测试 `test/env.test.ts`**

```ts
import { afterEach, describe, expect, it } from 'vitest';

describe('env', () => {
  afterEach(() => { delete process.env.FREE_DAILY_TRANSLATIONS; delete process.env.PRO_DAILY_TRANSLATIONS; });

  it('returns configured limits', async () => {
    process.env.FREE_DAILY_TRANSLATIONS = '7';
    process.env.PRO_DAILY_TRANSLATIONS = '999';
    const { reloadEnv, env } = await import('../lib/env.js');
    reloadEnv();
    expect(env.freeDailyTranslations).toBe(7);
    expect(env.proDailyTranslations).toBe(999);
  });

  it('falls back to defaults 20/500', async () => {
    const { reloadEnv, env } = await import('../lib/env.js');
    reloadEnv();
    expect(env.freeDailyTranslations).toBe(20);
    expect(env.proDailyTranslations).toBe(500);
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd geekread/backend && npx vitest run test/env.test.ts`
Expected: FAIL（`Cannot find module '../lib/env.js'`）。

- [ ] **Step 3: 实现 `lib/env.ts`**

```ts
export type Env = {
  modelApiUrl: string;
  modelApiKey: string;
  modelName: string;
  redisUrl: string;
  freeDailyTranslations: number;
  proDailyTranslations: number;
  entitlementSigningSecret: string;
  hackerNewsApiUrl: string;
};

function num(name: string, fallback: number): number {
  const raw = process.env[name]?.trim();
  const parsed = raw ? Number(raw) : fallback;
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

function str(name: string, fallback = ''): string {
  return process.env[name]?.trim() || fallback;
}

let cached: Env | undefined;
export function reloadEnv(): Env {
  cached = {
    modelApiUrl: str('MODEL_API_URL'),
    modelApiKey: str('MODEL_API_KEY'),
    modelName: str('MODEL_NAME'),
    redisUrl: str('REDIS_URL'),
    freeDailyTranslations: num('FREE_DAILY_TRANSLATIONS', 20),
    proDailyTranslations: num('PRO_DAILY_TRANSLATIONS', 500),
    entitlementSigningSecret: str('ENTITLEMENT_SIGNING_SECRET'),
    hackerNewsApiUrl: str('HACKER_NEWS_API_URL', 'https://hacker-news.firebaseio.com/v0'),
  };
  return cached;
}
export function env(): Env {
  return cached ?? reloadEnv();
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd geekread/backend && npx vitest run test/env.test.ts`
Expected: PASS（2 passed）。

- [ ] **Step 5: 提交**

```bash
cd geekread && git add backend/lib/env.ts backend/test/env.test.ts && git commit -m "feat(backend): env config module"
```

---

### Task 3: `lib/storage.ts` 移植 + 测试

**Files:**
- Create: `geekread/backend/lib/storage.ts`（移植自 `Hacki-OH/backend/src/storage.ts`，verbatim，**仅删除 `storeContentReport`/`pool()` 这段 PG 逻辑**——举报 v1 后置；保留 cache/SWR/quota）
- Test: `geekread/backend/test/storage.test.ts`

- [ ] **Step 1: 写失败测试 `test/storage.test.ts`**（不设 `REDIS_URL`，走内存 Map）

```ts
import { describe, expect, it, beforeEach } from 'vitest';

describe('storage (in-memory)', () => {
  beforeEach(() => { delete process.env.REDIS_URL; });

  it('caches and reads a translation', async () => {
    const { cacheTranslation, getCachedTranslation } = await import('../lib/storage.js');
    await cacheTranslation('hello', 'zh-Hans', '你好');
    expect(await getCachedTranslation('hello', 'zh-Hans')).toBe('你好');
    expect(await getCachedTranslation('bye', 'zh-Hans')).toBeUndefined();
  });

  it('reserves quota up to a limit then denies, with rollback', async () => {
    const { reserveTranslation } = await import('../lib/storage.js');
    const day = '2026-08-12';
    const a = await reserveTranslation(day, 'client-a', 2);
    expect(a.allowed).toBe(true);
    expect(a.remaining).toBe(1);
    const b = await reserveTranslation(day, 'client-a', 2);
    expect(b.allowed).toBe(true);
    expect(b.remaining).toBe(0);
    const c = await reserveTranslation(day, 'client-a', 2);
    expect(c.allowed).toBe(false);
    await b.rollback();
    const d = await reserveTranslation(day, 'client-a', 2);
    expect(d.allowed).toBe(true);
  });

  it('tracks separate clients separately', async () => {
    const { reserveTranslation } = await import('../lib/storage.js');
    const day = '2026-08-12';
    expect((await reserveTranslation(day, 'client-a', 1)).allowed).toBe(true);
    expect((await reserveTranslation(day, 'client-b', 1)).allowed).toBe(true);
    expect((await reserveTranslation(day, 'client-a', 1)).allowed).toBe(false);
  });

  it('serves stale JSON cache then expires', async () => {
    const { getJsonCache, setJsonCache } = await import('../lib/storage.js');
    await setJsonCache('k', [1, 2], 0, 100); // fresh 0s → immediately stale, expires +100s
    const hit = await getJsonCache<number[]>('k');
    expect(hit?.value).toEqual([1, 2]);
    expect(hit?.stale).toBe(true);
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd geekread/backend && npx vitest run test/storage.test.ts`
Expected: FAIL（`Cannot find module '../lib/storage.js'`）。

- [ ] **Step 3: 创建 `lib/storage.ts`**

把 `Hacki-OH/backend/src/storage.ts` 的内容**逐字复制**到 `geekread/backend/lib/storage.ts`，**删除 `pool()`、`storeContentReport()`、顶部的 `import pg` 与 `const { Pool } = pg;`**（PG/举报 v1 不需要）。保留：`createHash`/`redis` import、所有 cache/SWR/quota 函数、`storageConfiguration()`（改为只返 redis）。`storageConfiguration` 改为：

```ts
export function storageConfiguration(): { redis: boolean } {
  return { redis: Boolean(process.env.REDIS_URL?.trim()) };
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd geekread/backend && npx vitest run test/storage.test.ts`
Expected: PASS（4 passed）。

- [ ] **Step 5: 提交**

```bash
cd geekread && git add backend/lib/storage.ts backend/test/storage.test.ts && git commit -m "feat(backend): port storage (cache/SWR/quota) from Hacki-OH"
```

---

### Task 4: `lib/hacker-news.ts` 移植 + 测试

**Files:**
- Create: `geekread/backend/lib/hacker-news.ts`（verbatim 自 `Hacki-OH/backend/src/hacker-news.ts`）
- Test: `geekread/backend/test/hacker-news.test.ts`

- [ ] **Step 1: 写失败测试**（mock `fetch` + 不设 REDIS_URL）

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function mockFetch(map: Record<string, unknown>) {
  const spy = vi.fn(async (url: string | URL | Request) => {
    const path = String(typeof url === 'string' ? url : url.toString());
    const body = map[path] ?? map[path.replace(/^https:\/\/[^/]+/, '')];
    if (body === undefined) return new Response('not found', { status: 502 });
    return new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });
  });
  globalThis.fetch = spy as unknown as typeof fetch;
  return spy;
}

describe('hacker-news', () => {
  beforeEach(() => { delete process.env.REDIS_URL; delete process.env.HACKER_NEWS_API_URL; });
  afterEach(() => vi.restoreAllMocks());

  it('fetchStoryIds top returns integer ids', async () => {
    mockFetch({ '/topstories.json': [3, 2, 1], '/item/3.json': null });
    const { fetchStoryIds } = await import('../lib/hacker-news.js');
    const r = await fetchStoryIds('top');
    expect(r.ids).toEqual([3, 2, 1]);
    expect(r.cached).toBe(false);
  });

  it('rejects malformed story list', async () => {
    mockFetch({ '/topstories.json': { not: 'array' } });
    const { fetchStoryIds } = await import('../lib/hacker-news.js');
    await expect(fetchStoryIds('top')).rejects.toThrow();
  });

  it('fetchItems batch-loads and preserves order', async () => {
    mockFetch({
      '/item/1.json': { id: 1, title: 'a' },
      '/item/2.json': { id: 2, title: 'b' },
      '/item/3.json': null,
    });
    const { fetchItems } = await import('../lib/hacker-news.js');
    const r = await fetchItems([1, 2, 3]);
    expect(r.items.map((x) => x?.id)).toEqual([1, 2, undefined]);
  });

  it('serves cached items on upstream failure (stale)', async () => {
    mockFetch({ '/item/9.json': { id: 9, title: 'cached' } });
    const { fetchItems } = await import('../lib/hacker-news.js');
    const first = await fetchItems([9]);
    mockFetch({}); // upstream now broken
    const second = await fetchItems([9]);
    expect(second.items[0]).toEqual({ id: 9, title: 'cached' });
    expect(second.stale).toBe(true);
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd geekread/backend && npx vitest run test/hacker-news.test.ts`
Expected: FAIL（模块不存在）。

- [ ] **Step 3: 创建 `lib/hacker-news.ts`**

把 `Hacki-OH/backend/src/hacker-news.ts` **逐字复制**到 `geekread/backend/lib/hacker-news.ts`（95 行，含 `fetchStoryIds`/`fetchItem`/`fetchItems`/SWR）。无须改动。

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd geekread/backend && npx vitest run test/hacker-news.test.ts`
Expected: PASS（4 passed）。

- [ ] **Step 5: 提交**

```bash
cd geekread && git add backend/lib/hacker-news.ts backend/test/hacker-news.test.ts && git commit -m "feat(backend): port hacker-news proxy from Hacki-OH"
```

---

### Task 5: `lib/model.ts` 移植 + 测试

**Files:**
- Create: `geekread/backend/lib/model.ts`（verbatim 自 `Hacki-OH/backend/src/model.ts`）
- Test: `geekread/backend/test/model.test.ts`

- [ ] **Step 1: 写失败测试**（mock fetch；env 注入）

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function okResponse(content: string | unknown) {
  const body = typeof content === 'string'
    ? { choices: [{ message: { content } }] }
    : content;
  return new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });
}

describe('model', () => {
  beforeEach(() => {
    process.env.MODEL_API_URL = 'https://llm.example.com/chat';
    process.env.MODEL_API_KEY = 'k';
    process.env.MODEL_NAME = 'test-model';
  });
  afterEach(() => vi.restoreAllMocks());

  it('translates via OpenAI-compatible chat', async () => {
    const spy = vi.fn(async () => okResponse('你好'));
    globalThis.fetch = spy as unknown as typeof fetch;
    const { translateWithModel } = await import('../lib/model.js');
    expect(await translateWithModel('hello', 'zh-Hans')).toBe('你好');
    const body = JSON.parse((spy.mock.calls[0][1] as RequestInit).body as string);
    expect(body.messages[0].role).toBe('system');
    expect(body.messages[0].content).toContain('Simplified Chinese');
  });

  it('rejects unsupported language', async () => {
    const { translateWithModel } = await import('../lib/model.js');
    await expect(translateWithModel('hi', 'fr')).rejects.toThrow('unsupported_target_language');
  });

  it('rejects empty translation', async () => {
    globalThis.fetch = vi.fn(async () => okResponse('   ')) as unknown as typeof fetch;
    const { translateWithModel } = await import('../lib/model.js');
    await expect(translateWithModel('hi', 'zh-Hans')).rejects.toThrow('empty_translation');
  });

  it('surfaces upstream error status', async () => {
    globalThis.fetch = vi.fn(async () => new Response('err', { status: 500 })) as unknown as typeof fetch;
    const { translateWithModel } = await import('../lib/model.js');
    await expect(translateWithModel('hi', 'zh-Hans')).rejects.toThrow('model_upstream_500');
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd geekread/backend && npx vitest run test/model.test.ts`
Expected: FAIL（模块不存在）。

- [ ] **Step 3: 创建 `lib/model.ts`**

把 `Hacki-OH/backend/src/model.ts` **逐字复制**到 `geekread/backend/lib/model.ts`（70 行）。无须改动。

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd geekread/backend && npx vitest run test/model.test.ts`
Expected: PASS（4 passed）。

- [ ] **Step 5: 提交**

```bash
cd geekread && git add backend/lib/model.ts backend/test/model.test.ts && git commit -m "feat(backend): port LLM translation from Hacki-OH"
```

---

### Task 6: `lib/entitlement.ts`（验签 + 签发）+ 测试

**Files:**
- Create: `geekread/backend/lib/entitlement.ts`（从 `Hacki-OH/backend/src/function.ts` 的 `hasProEntitlement` 抽出 + 新增 `signEntitlement` 供测试/MobileStarter 参考用）
- Test: `geekread/backend/test/entitlement.test.ts`

> Token 格式（与 Hacki-OH 一致）：`base64url(payload).base64url(hmac_sha256(payload))`，payload 含 `{ exp }`。

- [ ] **Step 1: 写失败测试**

```ts
import { beforeEach, describe, expect, it } from 'vitest';

describe('entitlement', () => {
  beforeEach(() => { process.env.ENTITLEMENT_SIGNING_SECRET = 'secret'; });

  it('signs and verifies a pro token', async () => {
    const { signEntitlement, hasProEntitlement } = await import('../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) + 3600 });
    expect(hasProEntitlement(token)).toBe(true);
  });

  it('rejects expired token', async () => {
    const { signEntitlement, hasProEntitlement } = await import('../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) - 10 });
    expect(hasProEntitlement(token)).toBe(false);
  });

  it('rejects tampered signature', async () => {
    const { signEntitlement, hasProEntitlement } = await import('../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) + 3600 });
    expect(hasProEntitlement(token + 'x')).toBe(false);
  });

  it('returns false when no secret configured', async () => {
    delete process.env.ENTITLEMENT_SIGNING_SECRET;
    const { hasProEntitlement } = await import('../lib/entitlement.js');
    expect(hasProEntitlement('anything')).toBe(false);
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd geekread/backend && npx vitest run test/entitlement.test.ts`
Expected: FAIL（模块不存在）。

- [ ] **Step 3: 实现 `lib/entitlement.ts`**

```ts
import { createHmac, timingSafeEqual } from 'node:crypto';

export type EntitlementClaims = { exp: number; [k: string]: unknown };

export function signEntitlement(claims: EntitlementClaims): string {
  const secret = process.env.ENTITLEMENT_SIGNING_SECRET ?? '';
  if (!secret) throw new Error('entitlement_secret_not_configured');
  const payload = Buffer.from(JSON.stringify(claims)).toString('base64url');
  const signature = createHmac('sha256', secret).update(payload).digest('base64url');
  return `${payload}.${signature}`;
}

export function hasProEntitlement(token: string): boolean {
  const secret = process.env.ENTITLEMENT_SIGNING_SECRET ?? '';
  if (!token || !secret) return false;
  const [payload, signature] = token.split('.');
  if (!payload || !signature) return false;
  const expected = createHmac('sha256', secret).update(payload).digest('base64url');
  if (signature.length !== expected.length
    || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return false;
  try {
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString()) as { exp?: number };
    return Number(decoded.exp ?? 0) > Date.now() / 1000;
  } catch {
    return false;
  }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd geekread/backend && npx vitest run test/entitlement.test.ts`
Expected: PASS（4 passed）。

- [ ] **Step 5: 提交**

```bash
cd geekread && git add backend/lib/entitlement.ts backend/test/entitlement.test.ts && git commit -m "feat(backend): entitlement HMAC sign/verify"
```

---

### Task 7: `lib/quota.ts` + 测试

**Files:**
- Create: `geekread/backend/lib/quota.ts`
- Test: `geekread/backend/test/quota.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
import { beforeEach, describe, expect, it } from 'vitest';

describe('quota', () => {
  beforeEach(() => { delete process.env.REDIS_URL; process.env.ENTITLEMENT_SIGNING_SECRET = 's'; });

  it('free limit comes from env (20 default)', async () => {
    const { limitFor } = await import('../lib/quota.js');
    expect(limitFor(false)).toBe(20);
  });

  it('pro limit = proDailyTranslations', async () => {
    const { limitFor } = await import('../lib/quota.js');
    expect(limitFor(true)).toBe(500);
  });

  it('reserves against the right limit', async () => {
    process.env.FREE_DAILY_TRANSLATIONS = '1';
    const { reserveDaily } = await import('../lib/quota.js');
    const day = '2026-08-12';
    const r1 = await reserveDaily(day, 'c1', false);
    expect(r1.allowed).toBe(true);
    const r2 = await reserveDaily(day, 'c1', false);
    expect(r2.allowed).toBe(false);
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd geekread/backend && npx vitest run test/quota.test.ts`
Expected: FAIL（模块不存在）。

- [ ] **Step 3: 实现 `lib/quota.ts`**

```ts
import { env } from './env.js';
import { reserveTranslation } from './storage.js';

export function limitFor(isPro: boolean): number {
  return isPro ? env().proDailyTranslations : env().freeDailyTranslations;
}

export function today(): string {
  return new Date().toISOString().slice(0, 10);
}

export async function reserveDaily(day: string, clientId: string, isPro: boolean) {
  return reserveTranslation(day, clientId, limitFor(isPro));
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd geekread/backend && npx vitest run test/quota.test.ts`
Expected: PASS（3 passed）。

- [ ] **Step 5: 提交**

```bash
cd geekread && git add backend/lib/quota.ts backend/test/quota.test.ts && git commit -m "feat(backend): quota limit + daily reserve"
```

---

### Task 8: `lib/http.ts`（响应 + 校验 helper）

**Files:**
- Create: `geekread/backend/lib/http.ts`

- [ ] **Step 1: 实现 `lib/http.ts`**（纯 helper，无独立测试；由路由测试覆盖）

```ts
export function json(body: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...extraHeaders },
  });
}

export function errorResponse(message: string, status: number, extra: Record<string, unknown> = {}): Response {
  return json({ error: message, ...extra }, status);
}

export function requireString(value: unknown, maximum: number): string {
  if (typeof value !== 'string' || value.trim().length === 0 || value.length > maximum) {
    throw new Error('invalid_request');
  }
  return value.trim();
}

export function requireIds(value: unknown, max = 100): number[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > max) throw new Error('invalid_request');
  const ids = value.map((id) => Number(id));
  if (ids.some((id) => !Number.isSafeInteger(id) || id <= 0)) throw new Error('invalid_request');
  return ids;
}

export function safeErrorStatus(message: string): number {
  return message === 'invalid_request' ? 400
    : message === 'quota_exceeded' ? 429
    : message.startsWith('unsupported_') ? 400
    : 503;
}
```

- [ ] **Step 2: 类型检查**

Run: `cd geekread/backend && npx tsc --noEmit`
Expected: 无错误。

- [ ] **Step 3: 提交**

```bash
cd geekread && git add backend/lib/http.ts && git commit -m "feat(backend): http + validation helpers"
```

---

### Task 9: `GET /api/reader/stories` 路由 + 测试

**Files:**
- Create: `geekread/backend/app/api/reader/stories/route.ts`
- Test: `geekread/backend/test/routes/stories.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('GET /api/reader/stories', () => {
  beforeEach(() => { delete process.env.REDIS_URL; });
  afterEach(() => vi.restoreAllMocks());

  it('returns top story ids', async () => {
    globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
      const path = String(url).replace(/^https:\/\/[^/]+/, '');
      if (path === '/topstories.json') return new Response(JSON.stringify([7, 8]), { status: 200 });
      return new Response('nf', { status: 502 });
    }) as unknown as typeof fetch;
    const { GET } = await import('../../app/api/reader/stories/route.js');
    const res = await GET(new Request('http://localhost/api/reader/stories?type=top'));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ids).toEqual([7, 8]);
  });

  it('400 on bad type', async () => {
    const { GET } = await import('../../app/api/reader/stories/route.js');
    const res = await GET(new Request('http://localhost/api/reader/stories?type=hot'));
    expect(res.status).toBe(400);
  });

  it('maps latest to newstories', async () => {
    const spy = vi.fn(async () => new Response(JSON.stringify([1]), { status: 200 })) as unknown as typeof fetch;
    globalThis.fetch = spy;
    const { GET } = await import('../../app/api/reader/stories/route.js');
    await GET(new Request('http://localhost/api/reader/stories?type=latest'));
    expect(String((spy.mock.calls[0][0]))).toContain('/newstories.json');
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd geekread/backend && npx vitest run test/routes/stories.test.ts`
Expected: FAIL（路由模块不存在）。

- [ ] **Step 3: 实现 `app/api/reader/stories/route.ts`**

```ts
import { fetchStoryIds } from '../../../../lib/hacker-news.js';
import { errorResponse, json, safeErrorStatus } from '../../../../lib/http.js';

export async function GET(request: Request): Promise<Response> {
  const type = new URL(request.url).searchParams.get('type');
  if (type !== 'top' && type !== 'latest') return errorResponse('invalid_request', 400);
  try {
    const result = await fetchStoryIds(type);
    return json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, safeErrorStatus(message));
  }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd geekread/backend && npx vitest run test/routes/stories.test.ts`
Expected: PASS（3 passed）。

- [ ] **Step 5: 提交**

```bash
cd geekread && git add backend/app/api/reader/stories/route.ts backend/test/routes/stories.test.ts && git commit -m "feat(backend): GET /api/reader/stories"
```

---

### Task 10: `POST /api/reader/items` 路由 + 测试

**Files:**
- Create: `geekread/backend/app/api/reader/items/route.ts`
- Test: `geekread/backend/test/routes/items.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('POST /api/reader/items', () => {
  beforeEach(() => { delete process.env.REDIS_URL; });
  afterEach(() => vi.restoreAllMocks());

  it('returns items in order', async () => {
    globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
      const path = String(url).replace(/^https:\/\/[^/]+/, '');
      if (path === '/item/1.json') return new Response(JSON.stringify({ id: 1, title: 'a' }), { status: 200 });
      if (path === '/item/2.json') return new Response(JSON.stringify({ id: 2, title: 'b' }), { status: 200 });
      return new Response('nf', { status: 502 });
    }) as unknown as typeof fetch;
    const { POST } = await import('../../app/api/reader/items/route.js');
    const res = await POST(new Request('http://localhost/api/reader/items', {
      method: 'POST', body: JSON.stringify({ ids: [1, 2] }),
    }));
    const body = await res.json();
    expect(body.items.map((x: { id: number }) => x.id)).toEqual([1, 2]);
  });

  it('400 on empty ids', async () => {
    const { POST } = await import('../../app/api/reader/items/route.js');
    const res = await POST(new Request('http://localhost/api/reader/items', {
      method: 'POST', body: JSON.stringify({ ids: [] }),
    }));
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd geekread/backend && npx vitest run test/routes/items.test.ts`
Expected: FAIL（模块不存在）。

- [ ] **Step 3: 实现 `app/api/reader/items/route.ts`**

```ts
import { fetchItems } from '../../../../lib/hacker-news.js';
import { errorResponse, json, requireIds, safeErrorStatus } from '../../../../lib/http.js';

export async function POST(request: Request): Promise<Response> {
  let payload: unknown;
  try { payload = await request.json(); } catch { return errorResponse('invalid_request', 400); }
  try {
    const ids = requireIds((payload as { ids?: unknown }).ids);
    return json(await fetchItems(ids));
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, safeErrorStatus(message));
  }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd geekread/backend && npx vitest run test/routes/items.test.ts`
Expected: PASS（2 passed）。

- [ ] **Step 5: 提交**

```bash
cd geekread && git add backend/app/api/reader/items/route.ts backend/test/routes/items.test.ts && git commit -m "feat(backend): POST /api/reader/items"
```

---

### Task 11: `POST /api/translate` 路由（批处理 + 缓存 + 配额 + entitlement）+ 测试

**Files:**
- Create: `geekread/backend/app/api/translate/route.ts`
- Test: `geekread/backend/test/routes/translate.test.ts`

> 逻辑移植自 `Hacki-OH/backend/src/function.ts` 的 `handleTranslationBatch`（4 并发 worker、cache 优先、配额预约 + rollback、pro 判定）。把 callable payload 读取换成读 Request + 头；客户端身份从 `x-install-id` 头取（缺省拒）。

- [ ] **Step 1: 写失败测试**

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function llm(map: Record<string, string>) {
  return vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body ?? '{}')) as { messages: { content: string }[] };
    const src = body.messages[1].content;
    const out = map[src] ?? 'TRANSLATED';
    return new Response(JSON.stringify({ choices: [{ message: { content: out } }] }), { status: 200 });
  }) as unknown as typeof fetch;
}

describe('POST /api/translate', () => {
  beforeEach(() => {
    delete process.env.REDIS_URL;
    process.env.MODEL_API_URL = 'https://llm/chat'; process.env.MODEL_API_KEY = 'k'; process.env.MODEL_NAME = 'm';
    process.env.ENTITLEMENT_SIGNING_SECRET = 's'; process.env.FREE_DAILY_TRANSLATIONS = '20';
  });
  afterEach(() => vi.restoreAllMocks());

  it('translates a batch and returns keyed results', async () => {
    globalThis.fetch = llm({ hello: '你好' });
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c1' },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries: [{ key: 'k1', text: 'hello' }] }),
    }));
    const body = await res.json();
    expect(body.results[0]).toMatchObject({ key: 'k1', translation: '你好' });
    expect(body.remainingTranslations).toBe(19);
  });

  it('serves cached translation without consuming quota', async () => {
    const { cacheTranslation } = await import('../../lib/storage.js');
    await cacheTranslation('hello', 'zh-Hans', '你好');
    const fetchSpy = vi.fn();
    globalThis.fetch = fetchSpy as unknown as typeof fetch;
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c1' },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries: [{ key: 'k1', text: 'hello' }] }),
    }));
    const body = await res.json();
    expect(body.results[0]).toMatchObject({ key: 'k1', translation: '你好', cached: true });
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('returns quota_exceeded when free limit hit', async () => {
    process.env.FREE_DAILY_TRANSLATIONS = '1';
    globalThis.fetch = llm({});
    const { POST } = await import('../../app/api/translate/route.js');
    const req = (entries: { key: string; text: string }[]) => new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c2' },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries }),
    });
    await POST(req([{ key: 'a', text: 'first' }]));
    const res2 = await POST(req([{ key: 'b', text: 'second' }]));
    const body2 = await res2.json();
    expect(body2.results[0].error).toBe('quota_exceeded');
  });

  it('Pro entitlement raises the limit', async () => {
    process.env.FREE_DAILY_TRANSLATIONS = '0';
    process.env.PRO_DAILY_TRANSLATIONS = '500';
    const { signEntitlement } = await import('../../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) + 3600 });
    globalThis.fetch = llm({});
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c3', authorization: `Bearer ${token}` },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries: [{ key: 'a', text: 'hi' }] }),
    }));
    const body = await res.json();
    expect(body.results[0].translation).toBe('TRANSLATED');
  });

  it('400 when install id missing', async () => {
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries: [{ key: 'a', text: 'hi' }] }),
    }));
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `cd geekread/backend && npx vitest run test/routes/translate.test.ts`
Expected: FAIL（模块不存在）。

- [ ] **Step 3: 实现 `app/api/translate/route.ts`**

```ts
import { hasProEntitlement } from '../../../lib/entitlement.js';
import { errorResponse, json, requireString, safeErrorStatus } from '../../../lib/http.js';
import { translateWithModel } from '../../../lib/model.js';
import { reserveDaily, today } from '../../../lib/quota.js';
import { cacheTranslation, getCachedTranslation } from '../../../lib/storage.js';

const SUPPORTED = new Set(['en', 'ja', 'ko', 'zh-Hans', 'zh-Hant']);
const MAX_ENTRIES = 20;
const MAX_TOTAL_CHARS = 12_000;

type Entry = { key: string; text: string };
type Result = { key: string; translation?: string; cached?: boolean; error?: string };

export async function POST(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0 || installId.length > 128) {
    return errorResponse('invalid_request', 400);
  }
  const auth = request.headers.get('authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(auth);
  const isPro = match ? hasProEntitlement(match[1].trim()) : false;

  let payload: unknown;
  try { payload = await request.json(); } catch { return errorResponse('invalid_request', 400); }

  try {
    const targetLanguage = requireString((payload as { targetLanguage?: unknown }).targetLanguage, 20);
    if (!SUPPORTED.has(targetLanguage)) throw new Error('unsupported_target_language');
    const rawEntries = (payload as { entries?: unknown }).entries;
    if (!Array.isArray(rawEntries) || rawEntries.length === 0 || rawEntries.length > MAX_ENTRIES) {
      throw new Error('invalid_request');
    }
    const entries: Entry[] = rawEntries.map((v) => {
      if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Error('invalid_request');
      const e = v as { key?: unknown; text?: unknown };
      return { key: requireString(e.key, 256), text: requireString(e.text, 12_000) };
    });
    if (entries.reduce((n, e) => n + e.text.length, 0) > MAX_TOTAL_CHARS) throw new Error('invalid_request');

    const day = today();
    const results: Result[] = new Array(entries.length);
    let remaining: number | undefined;
    let nextIndex = 0;

    async function worker(): Promise<void> {
      while (nextIndex < entries.length) {
        const index = nextIndex++;
        const entry = entries[index];
        if (!entry) return;
        try {
          const cached = await getCachedTranslation(entry.text, targetLanguage);
          if (cached) { results[index] = { key: entry.key, translation: cached, cached: true }; continue; }
          const reservation = await reserveDaily(day, installId, isPro);
          if (!reservation.allowed) { results[index] = { key: entry.key, error: 'quota_exceeded' }; remaining = 0; continue; }
          remaining = remaining === undefined ? reservation.remaining : Math.min(remaining, reservation.remaining);
          try {
            const translation = await translateWithModel(entry.text, targetLanguage);
            await cacheTranslation(entry.text, targetLanguage, translation);
            results[index] = { key: entry.key, translation };
          } catch (error) {
            await reservation.rollback();
            results[index] = { key: entry.key, error: error instanceof Error ? error.message : 'translation_failed' };
          }
        } catch (error) {
          results[index] = { key: entry.key, error: error instanceof Error ? error.message : 'translation_failed' };
        }
      }
    }

    await Promise.all(Array.from({ length: Math.min(4, entries.length) }, () => worker()));
    return json({ results, ...(remaining === undefined ? {} : { remainingTranslations: remaining }) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, safeErrorStatus(message));
  }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `cd geekread/backend && npx vitest run test/routes/translate.test.ts`
Expected: PASS（5 passed）。

- [ ] **Step 5: 跑全量测试 + 类型检查**

Run: `cd geekread/backend && npx vitest run && npx tsc --noEmit`
Expected: 全部测试通过，类型无错。

- [ ] **Step 6: 提交**

```bash
cd geekread && git add backend/app/api/translate/route.ts backend/test/routes/translate.test.ts && git commit -m "feat(backend): POST /api/translate (batch/cache/quota/entitlement)"
```

---

### Task 12: README + Dockerfile

**Files:**
- Create: `geekread/backend/README.md`
- Create: `geekread/backend/Dockerfile`

- [ ] **Step 1: 建 `README.md`**

```markdown
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

`docker build -t geekread-backend .` → 任一容器平台（Vercel/华为云 CCE）。国内部署需备案。
```

- [ ] **Step 2: 建 `Dockerfile`**

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:22-alpine AS run
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/.next ./.next
COPY --from=build /app/public ./public
COPY --from=build /app/package.json ./package.json
COPY --from=deps /app/node_modules ./node_modules
EXPOSE 8787
CMD ["npm","start"]
```

- [ ] **Step 3: 提交**

```bash
cd geekread && git add backend/README.md backend/Dockerfile && git commit -m "feat(backend): README + Dockerfile"
```

---

### Task 13: `shared/api-schema.json` + TS 类型 codegen

**Files:**
- Create: `geekread/shared/api-schema.json`
- Create: `geekread/shared/codegen/gen-types.mjs`
- Create: `geekread/shared/generated/types.ts`（生成产物）

- [ ] **Step 1: 建 `shared/api-schema.json`**（极简 JSON Schema，描述三个端点的请求/响应；后续 RN/ArkTS 都从此生成）

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "GeekRead API",
  "definitions": {
    "StoryType": { "type": "string", "enum": ["top", "latest"] },
    "StoriesResponse": {
      "type": "object",
      "required": ["ids", "cached", "stale"],
      "properties": {
        "ids": { "type": "array", "items": { "type": "integer" } },
        "cached": { "type": "boolean" },
        "stale": { "type": "boolean" }
      }
    },
    "ItemsRequest": {
      "type": "object", "required": ["ids"],
      "properties": { "ids": { "type": "array", "items": { "type": "integer" }, "minItems": 1, "maxItems": 100 } }
    },
    "HNItem": {
      "type": "object",
      "properties": {
        "id": { "type": "integer" },
        "type": { "type": "string" },
        "by": { "type": "string" },
        "time": { "type": "integer" },
        "title": { "type": "string" },
        "url": { "type": "string" },
        "text": { "type": "string" },
        "score": { "type": "integer" },
        "descendants": { "type": "integer" },
        "kids": { "type": "array", "items": { "type": "integer" } },
        "parent": { "type": "integer" },
        "parts": { "type": "array", "items": { "type": "integer" } },
        "deleted": { "type": "boolean" },
        "dead": { "type": "boolean" }
      }
    },
    "ItemsResponse": {
      "type": "object", "required": ["items", "cached", "stale"],
      "properties": {
        "items": { "type": "array", "items": { "oneOf": [{ "$ref": "#/definitions/HNItem" }, { "type": "null" }] } },
        "cached": { "type": "boolean" },
        "stale": { "type": "boolean" }
      }
    },
    "TargetLanguage": { "type": "string", "enum": ["en", "ja", "ko", "zh-Hans", "zh-Hant"] },
    "TranslateEntry": {
      "type": "object", "required": ["key", "text"],
      "properties": { "key": { "type": "string", "maxLength": 256 }, "text": { "type": "string", "maxLength": 12000 } }
    },
    "TranslateRequest": {
      "type": "object", "required": ["targetLanguage", "entries"],
      "properties": {
        "targetLanguage": { "$ref": "#/definitions/TargetLanguage" },
        "entries": { "type": "array", "items": { "$ref": "#/definitions/TranslateEntry" }, "minItems": 1, "maxItems": 20 }
      }
    },
    "TranslateResult": {
      "type": "object", "required": ["key"],
      "properties": {
        "key": { "type": "string" },
        "translation": { "type": "string" },
        "cached": { "type": "boolean" },
        "error": { "type": "string" }
      }
    },
    "TranslateResponse": {
      "type": "object", "required": ["results"],
      "properties": {
        "results": { "type": "array", "items": { "$ref": "#/definitions/TranslateResult" } },
        "remainingTranslations": { "type": "integer" },
        "error": { "type": "string" }
      }
    },
    "ErrorResponse": {
      "type": "object", "required": ["error"],
      "properties": { "error": { "type": "string" } }
    }
  }
}
```

- [ ] **Step 2: 建 `shared/codegen/gen-types.mjs`**（手写极简 codegen：读 schema → 吐 TS interface；避免引第三方依赖）

```js
// shared/codegen/gen-types.mjs
// 极简 JSON-schema → TS interface 生成器，覆盖本项目用到的子集（object/integer/string/boolean/array/enum/null/oneOf）。
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const schemaPath = join(here, '..', 'api-schema.json');
const outPath = join(here, '..', 'generated', 'types.ts');
const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));

function tsType(node) {
  if (node.$ref) return node.$ref.replace('#/definitions/', '');
  if (node.enum) return node.enum.map((v) => JSON.stringify(v)).join(' | ');
  switch (node.type) {
    case 'integer': return 'number';
    case 'number': return 'number';
    case 'boolean': return 'boolean';
    case 'string': return 'string';
    case 'null': return 'null';
    case 'array': return `Array<${tsType(node.items)}>`;
    case 'object': return inlineObject(node);
    case undefined:
      if (node.oneOf) return `(${node.oneOf.map(tsType).join(' | ')})`;
      return 'unknown';
    default: return 'unknown';
  }
}
function inlineObject(node) {
  const props = node.properties ?? {};
  const required = new Set(node.required ?? []);
  const fields = Object.entries(props).map(([name, sub]) => {
    const opt = required.has(name) ? '' : '?';
    return `  ${name}${opt}: ${tsType(sub)};`;
  });
  return `{\n${fields.join('\n')}\n}`;
}

const defs = schema.definitions ?? {};
const blocks = Object.entries(defs).map(([name, node]) => {
  const t = tsType(node);
  return t.startsWith('{') ? `export interface ${name} ${t}` : `export type ${name} = ${t};`;
});

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath,
  `// AUTO-GENERATED by shared/codegen/gen-types.mjs — do not edit.\n` +
  `// Source: shared/api-schema.json\n\n` +
  blocks.join('\n\n') + '\n');
console.log(`generated ${outPath}`);
```

- [ ] **Step 3: 跑 codegen，确认产物**

Run: `cd geekread/shared && node codegen/gen-types.mjs && cat generated/types.ts`
Expected: 打印 `generated .../types.ts`；产物含 `interface StoriesResponse`、`type StoryType = "top" | "latest"`、`interface TranslateRequest` 等。

- [ ] **Step 4: 提交**

```bash
cd geekread && git add shared && git commit -m "feat(shared): API JSON schema + TS codegen"
```

---

### Task 14: 端到端冒烟（真起 dev server + curl）

**Files:** 无新建（验证）

- [ ] **Step 1: 起 dev server（后台）**

Run: `cd geekread/backend && (npm run dev > /tmp/geekread-backend.log 2>&1 &) && sleep 8 && cat /tmp/geekread-backend.log`
Expected: 日志显示 `Ready`，监听 8787。

- [ ] **Step 2: curl stories**

Run: `curl -s 'http://localhost:8787/api/reader/stories?type=top' | head -c 200`
Expected: 返回 `{"ids":[...],"cached":false,"stale":false}`（真实 HN 数据；无 `REDIS_URL` 走内存）。

- [ ] **Step 3: curl items**

Run: `curl -s -X POST http://localhost:8787/api/reader/items -H 'content-type: application/json' -d '{"ids":[1]}' | head -c 300`
Expected: 返回 `{"items":[{...HN item 1...}],"cached":false,"stale":false}`。

- [ ] **Step 4: curl translate（缺 LLM 密钥时返回 503 `model_not_configured`；验证链路通即可）**

Run: `curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8787/api/translate -H 'content-type: application/json' -H 'x-install-id: smoke' -d '{"targetLanguage":"zh-Hans","entries":[{"key":"k1","text":"hello"}]}'`
Expected: `200`（若已配真实 LLM 密钥）或 `503`（未配密钥）。任一都证明路由/校验/配额链路通；404/500 才是失败。

- [ ] **Step 5: 关停 dev server**

Run: `pkill -f "next dev -p 8787" || true`
Expected: 进程结束。

- [ ] **Step 6: 更新 spec 验收勾选 + 提交冒烟记录**

在 `docs/superpowers/specs/2026-08-12-geek-reader-design.md` 的「v1 验收标准」里勾掉「极客译读 Next.js 后端独立部署，HN 代理 + 翻译 + 配额 + entitlement 验签工作」一项的 HN 代理/配额/验签部分（翻译完整闭环待 LLM 密钥）。

```bash
cd geekread && git add docs && git commit -m "docs: foundation backend smoke verified"
```

---

## Self-Review（plan 作者自检）

**Spec 覆盖**：
- §4 架构（专属 Next.js）→ Tasks 1–12 ✓
- §7 数据流（stories/items/translate）→ Tasks 9–11 ✓
- §10 后端移植表逐行 → hacker-news(T4)/model(T5)/storage(T3)/function→route(T11)/entitlement(T6)；`agc-function.ts`/`server.ts` 删除 ✓
- §11 Pro 权益闭环（JWT 验签）→ T6 + T11 ✓；签发侧（MobileStarter server）在 Plan 4
- §9 共享契约 → T13 ✓（ArkTS codegen 留 Plan 3）
- v1 范围内的搜索/离线/网页翻译 = v2，本计划不含 ✓

**占位符扫描**：无 TBD/TODO；所有步骤含完整代码或精确 verbatim 复制指令（源文件路径给死）。✓

**类型一致性**：`reserveDaily(day, clientId, isPro)`（T7）与 T11 调用一致；`hasProEntitlement(token)`（T6）与 T11 一致；`requireString/requireIds/safeErrorStatus`（T8）与 T9–T11 一致；`StoryType`/`TargetLanguage` 在 schema（T13）与路由校验一致。✓

**已知边界**：
- 评论树客户端递归 `/reader/items`（无独立 comments 端点）—— 与 Hacki-OH 架构一致，Plan 2/3 客户端实现。
- ArkTS 侧 codegen（schema → ArkTS interface）留到 Plan 3，避免 Plan 1 过大。
- entitlement **签发**（MobileStarter server 侧）在 Plan 4；本计划只做**验签**。
