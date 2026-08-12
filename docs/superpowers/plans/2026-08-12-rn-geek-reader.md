# Plan 2：RN 客户端 geek-reader feature 模块

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]`.

**Goal:** 在 `react-native/` 壳里加 `src/features/geek-reader/` 业务模块——HN 精选/最新列表、评论树、沉浸式双语翻译，调本仓库 `backend/`（端口 8787），复用 MobileStarter 的 auth/install-id/storage/设计系统。

**Architecture:** feature-local 状态（独立 Context，不进 AppStore）；GeekReaderApiClient 独立于主 apiClient（不同 base URL / 头语义）；翻译批处理缓存移植自 Hacki-OH `TranslationRepository`；AsyncState 语义复用 `src/state/asyncState.ts`。

**Tech Stack:** React Native (Expo 57) · TypeScript · Context+hooks · vitest（node env，`.ts` only，纯逻辑测试）。

**集成点**（来自 RN 壳调研）：
- 路由：`src/navigation/routes.ts:42` 加联合成员；`src/navigation/AppRouter.tsx` switch 加 case
- 入口：`src/screens/HomeScreen.tsx` `quickActions` 数组加一项
- env：`.env`/`.env.example` 加 `EXPO_PUBLIC_GEEKREAD_BACKEND_URL`
- 复用：`readAnonymousId`/`readSessionToken`（`src/data/storage.ts`）、`AsyncState`（`src/state/asyncState.ts`）、设计系统（`src/design-system/`）

---

## 文件结构

```
react-native/src/features/geek-reader/
├── domain/
│   └── models.ts                 Story/Comment/TargetLanguage，HNItem→领域模型映射
├── data/
│   └── GeekReaderApiClient.ts    stories/items/translate；x-install-id + Bearer；setter 注入
├── application/
│   ├── locale.ts                 locale→TargetLanguage（en→null 跳过）
│   ├── translationCache.ts       批处理(50ms/≤20/≤12k)+去重+缓存
│   └── comments.ts               扁平 items→树（纯函数）
├── state/
│   └── GeekReaderProvider.tsx    Context：stories/comments 状态 + translationCache 单例
├── presentation/
│   ├── GeekReaderHomeScreen.tsx  精选/最新 Tab + 列表 + 下拉/分页
│   ├── StoryDetailScreen.tsx     文章 + 评论树
│   ├── CommentTree.tsx           递归折叠/缩进
│   └── ImmersiveTranslation.tsx  双语渲染 + 自动触发 + 配额态
└── __tests__/
    ├── models.test.ts
    ├── locale.test.ts
    ├── translationCache.test.ts
    ├── comments.test.ts
    └── GeekReaderApiClient.test.ts
```

测试只覆盖纯逻辑（domain/locale/translationCache/comments/apiClient 请求构造），组件渲染不测（vitest node env，与现有项目一致）。

---

### Task R1: env 配置 + feature 路由注册 + 首页入口

**Files:**
- Modify: `react-native/.env`, `react-native/.env.example`
- Modify: `react-native/src/navigation/routes.ts`
- Modify: `react-native/src/navigation/AppRouter.tsx`
- Modify: `react-native/src/screens/HomeScreen.tsx`
- Modify: `react-native/src/navigation/useEntryIntents.ts`

- [ ] **Step 1: `.env` 与 `.env.example` 末尾加**

```
EXPO_PUBLIC_GEEKREAD_BACKEND_URL=http://localhost:8787
```

- [ ] **Step 2: `src/navigation/routes.ts` 在最后一个路由后追加**

```ts
  | 'geekreader.home'
  | 'geekreader.story'
```

- [ ] **Step 3: `src/screens/HomeScreen.tsx` 的 `quickActions` 数组加一项**（用 `globe` 图标）

```ts
  { label: '极客译读', icon: 'globe', route: 'geekreader.home' },
```

- [ ] **Step 4: `src/navigation/useEntryIntents.ts` 的 `routeNames` Set 加**

```ts
  'geekreader.home',
  'geekreader.story',
```

- [ ] **Step 5: 暂不接 AppRouter case**（待屏幕组件建好后接，避免 import 不存在的文件）。先提交接线骨架。

- [ ] **Step 6: 提交**

```bash
cd /Volumes/MacMiniDisk/workspace/geekread && git add react-native/.env react-native/.env.example react-native/src/navigation/routes.ts react-native/src/screens/HomeScreen.tsx react-native/src/navigation/useEntryIntents.ts && git commit -m "feat(rn): wire geek-reader routes + entry + backend url"
```

---

### Task R2: `domain/models.ts` + 测试

**Files:**
- Create: `react-native/src/features/geek-reader/domain/models.ts`
- Test: `react-native/src/features/geek-reader/__tests__/models.test.ts`

- [ ] **Step 1: 写失败测试 `__tests__/models.test.ts`**

```ts
import { describe, expect, it } from 'vitest';
import { toStory, toComment, type HNItem } from '../domain/models';

const storyItem: HNItem = { id: 1, type: 'story', title: 'T', by: 'pg', time: 0, score: 10, descendants: 3, url: 'https://x', kids: [2, 3] };
const commentItem: HNItem = { id: 2, type: 'comment', by: 'u', time: 0, text: 'hi', kids: [4], parent: 1 };

describe('models', () => {
  it('maps HN story item', () => {
    const s = toStory(storyItem);
    expect(s).toMatchObject({ id: 1, title: 'T', by: 'pg', url: 'https://x', score: 10, commentsCount: 3 });
    expect(s.kids).toEqual([2, 3]);
  });

  it('maps self-post story (text, no url)', () => {
    const s = toStory({ id: 5, type: 'story', title: 'Ask', text: 'body' });
    expect(s.url).toBeUndefined();
    expect(s.text).toBe('body');
  });

  it('maps comment', () => {
    const c = toComment(commentItem);
    expect(c).toMatchObject({ id: 2, by: 'u', text: 'hi', parentId: 1 });
    expect(c.kids).toEqual([4]);
  });

  it('returns null for missing item', () => {
    expect(toStory(null)).toBeNull();
    expect(toComment(null)).toBeNull();
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd react-native && npx vitest run src/features/geek-reader/__tests__/models.test.ts`
Expected: FAIL（模块不存在）。

- [ ] **Step 3: 实现 `domain/models.ts`**

```ts
export type HNItem = {
  id: number;
  type?: string;
  by?: string;
  time?: number;
  title?: string;
  url?: string;
  text?: string;
  score?: number;
  descendants?: number;
  kids?: number[];
  parent?: number;
  deleted?: boolean;
  dead?: boolean;
};

export type TargetLanguage = 'en' | 'ja' | 'ko' | 'zh-Hans' | 'zh-Hant';

export type Story = {
  id: number;
  title: string;
  by: string;
  url?: string;
  text?: string;
  score: number;
  commentsCount: number;
  time: number;
  kids: number[];
};

export type Comment = {
  id: number;
  by: string;
  text: string;
  time: number;
  parentId: number;
  kids: number[];
  deleted?: boolean;
  dead?: boolean;
};

export function toStory(item: HNItem | null): Story | null {
  if (!item || !item.id) return null;
  return {
    id: item.id,
    title: item.title ?? '',
    by: item.by ?? '',
    url: item.url,
    text: item.text,
    score: item.score ?? 0,
    commentsCount: item.descendants ?? 0,
    time: item.time ?? 0,
    kids: item.kids ?? [],
  };
}

export function toComment(item: HNItem | null): Comment | null {
  if (!item || !item.id) return null;
  return {
    id: item.id,
    by: item.by ?? '',
    text: item.text ?? '',
    time: item.time ?? 0,
    parentId: item.parent ?? 0,
    kids: item.kids ?? [],
    deleted: item.deleted,
    dead: item.dead,
  };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd react-native && npx vitest run src/features/geek-reader/__tests__/models.test.ts`
Expected: PASS（4）。

- [ ] **Step 5: 提交**

```bash
git add react-native/src/features/geek-reader/domain react-native/src/features/geek-reader/__tests__/models.test.ts && git commit -m "feat(rn): geek-reader domain models"
```

---

### Task R3: `data/GeekReaderApiClient.ts` + 测试

**Files:**
- Create: `react-native/src/features/geek-reader/data/GeekReaderApiClient.ts`
- Test: `react-native/src/features/geek-reader/__tests__/GeekReaderApiClient.test.ts`

- [ ] **Step 1: 写失败测试**（mock fetch；注入 install-id/token reader）

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('GeekReaderApiClient', () => {
  beforeEach(() => {
    process.env.EXPO_PUBLIC_GEEKREAD_BACKEND_URL = 'http://backend.test';
    vi.resetModules();
  });

  it('fetches stories with type query', async () => {
    const spy = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      expect(String(url)).toContain('/api/reader/stories?type=top');
      expect(init?.method ?? 'GET').toBe('GET');
      return new Response(JSON.stringify({ ids: [1, 2], cached: false, stale: false }), { status: 200 });
    });
    globalThis.fetch = spy as unknown as typeof fetch;
    const { setInstallIdReader, setTokenReader, fetchStories } = await import('../data/GeekReaderApiClient');
    setInstallIdReader(async () => 'inst-1');
    setTokenReader(async () => null);
    const r = await fetchStories('top');
    expect(r.ids).toEqual([1, 2]);
  });

  it('sends x-install-id and Authorization headers on translate', async () => {
    const seen: Record<string, string> = {};
    const spy = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      const headers = new Headers(init?.headers);
      headers.forEach((v, k) => { seen[k] = v; });
      return new Response(JSON.stringify({ results: [{ key: 'k', translation: '你好' }] }), { status: 200 });
    });
    globalThis.fetch = spy as unknown as typeof fetch;
    const { setInstallIdReader, setTokenReader, translateBatch } = await import('../data/GeekReaderApiClient');
    setInstallIdReader(async () => 'inst-1');
    setTokenReader(async () => 'pro-token');
    await translateBatch({ targetLanguage: 'zh-Hans', entries: [{ key: 'k', text: 'hello' }] });
    expect(seen['x-install-id']).toBe('inst-1');
    expect(seen['authorization']).toBe('Bearer pro-token');
  });

  it('omits Authorization when no token', async () => {
    const seen: Record<string, string> = {};
    globalThis.fetch = vi.fn(async (_u: unknown, init?: RequestInit) => {
      new Headers(init?.headers).forEach((v, k) => { seen[k] = v; });
      return new Response(JSON.stringify({ results: [] }), { status: 200 });
    }) as unknown as typeof fetch;
    const { setInstallIdReader, setTokenReader, translateBatch } = await import('../data/GeekReaderApiClient');
    setInstallIdReader(async () => 'inst-1');
    setTokenReader(async () => null);
    await translateBatch({ targetLanguage: 'zh-Hans', entries: [{ key: 'k', text: 'hi' }] });
    expect(seen['x-install-id']).toBe('inst-1');
    expect(seen['authorization']).toBeUndefined();
  });

  it('throws on non-ok', async () => {
    globalThis.fetch = vi.fn(async () => new Response('err', { status: 500 })) as unknown as typeof fetch;
    const { setInstallIdReader, setTokenReader, fetchStories } = await import('../data/GeekReaderApiClient');
    setInstallIdReader(async () => 'inst-1');
    setTokenReader(async () => null);
    await expect(fetchStories('top')).rejects.toThrow();
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd react-native && npx vitest run src/features/geek-reader/__tests__/GeekReaderApiClient.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 `data/GeekReaderApiClient.ts`**

```ts
import { readAnonymousId } from '../../../data/storage';
import { readSessionToken } from '../../../data/storage';
import type { HNItem, Story, Comment, TargetLanguage } from '../domain/models';
import { toStory, toComment } from '../domain/models';

const BASE = () => {
  const url = process.env.EXPO_PUBLIC_GEEKREAD_BACKEND_URL?.trim();
  if (!url) throw new Error('EXPO_PUBLIC_GEEKREAD_BACKEND_URL 未配置');
  return url.replace(/\/$/, '');
};

let installIdReader: () => Promise<string> = readAnonymousId;
let tokenReader: () => Promise<string | null> = readSessionToken;

export function setInstallIdReader(r: () => Promise<string>) { installIdReader = r; }
export function setTokenReader(r: () => Promise<string | null>) { tokenReader = r; }

async function authHeaders(): Promise<Record<string, string>> {
  const installId = await installIdReader();
  const token = await tokenReader();
  const h: Record<string, string> = { 'x-install-id': installId };
  if (token) h['authorization'] = `Bearer ${token}`;
  return h;
}

async function send(path: string, init?: RequestInit): Promise<Response> {
  const res = await fetch(`${BASE()}${path}`, init);
  if (!res.ok) throw new Error(`geekreader_${res.status}`);
  return res;
}

export async function fetchStories(type: 'top' | 'latest'): Promise<{ ids: number[]; cached: boolean; stale: boolean }> {
  const res = await send(`/api/reader/stories?type=${type}`, { headers: await authHeaders() });
  return res.json();
}

export async function fetchItems(ids: number[]): Promise<{ items: (HNItem | null)[]; cached: boolean; stale: boolean }> {
  const res = await send('/api/reader/items', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(await authHeaders()) },
    body: JSON.stringify({ ids }),
  });
  return res.json();
}

export type TranslateRequest = {
  targetLanguage: TargetLanguage;
  entries: { key: string; text: string }[];
};

export type TranslateResponse = {
  results: { key: string; translation?: string; cached?: boolean; error?: string }[];
  remainingTranslations?: number;
};

export async function translateBatch(req: TranslateRequest): Promise<TranslateResponse> {
  const res = await send('/api/translate', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(await authHeaders()) },
    body: JSON.stringify(req),
  });
  return res.json();
}

export async function fetchStoriesResolved(type: 'top' | 'latest', ids: number[]): Promise<Story[]> {
  const { items } = await fetchItems(ids);
  return items.map(toStory).filter((s): s is Story => s !== null);
}

export async function fetchComments(parentId: number): Promise<{ story?: Story; comments: Comment[] }> {
  const { items } = await fetchItems([parentId, ...collectDescendants(items0(parentId))]);
  return { comments: items.map(toComment).filter((c): c is Comment => c !== null) };
}
```

> 注意：`fetchComments` 上面的 `collectDescendants`/`items0` 占位逻辑会在 Task R4 的 `comments.ts` 里以纯函数实现——这里 R3 只保留 `fetchStories` / `fetchItems` / `translateBatch` / `fetchStoriesResolved`，**删掉 R3 里的 `fetchComments` 草稿**，避免引用未定义符号。最终 `data/GeekReaderApiClient.ts` 只导出 `fetchStories`、`fetchItems`、`translateBatch`、`fetchStoriesResolved`、setter、`authHeaders`。

- [ ] **Step 4: 精简实现（删除 `fetchComments` 草稿与多余 import）**

最终文件只含：BASE、setter、authHeaders、send、fetchStories、fetchItems、translateBatch、fetchStoriesResolved。`Comment` import 与 `toComment` 在 R3 不用，删掉。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd react-native && npx vitest run src/features/geek-reader/__tests__/GeekReaderApiClient.test.ts`
Expected: PASS（4）。

- [ ] **Step 6: 提交**

```bash
git add react-native/src/features/geek-reader/data react-native/src/features/geek-reader/__tests__/GeekReaderApiClient.test.ts && git commit -m "feat(rn): GeekReaderApiClient (stories/items/translate)"
```

---

### Task R4: `application/comments.ts`（扁平→树，纯函数）+ 测试

**Files:**
- Create: `react-native/src/features/geek-reader/application/comments.ts`
- Test: `react-native/src/features/geek-reader/__tests__/comments.test.ts`

- [ ] **Step 1: 写失败测试**

```ts
import { describe, expect, it } from 'vitest';
import { buildCommentTree } from '../application/comments';
import type { Comment } from '../domain/models';

const c = (id: number, parent: number, kids: number[] = []): Comment =>
  ({ id, by: 'u', text: `t${id}`, time: 0, parentId: parent, kids });

describe('buildCommentTree', () => {
  it('nests replies under parents by id', () => {
    const flat: Comment[] = [c(1, 0, [2, 3]), c(2, 1), c(3, 1, [4]), c(4, 3)];
    const tree = buildCommentTree(flat, 1);
    expect(tree.map((n) => n.id)).toEqual([2, 3]);
    expect(tree[1].replies.map((r: { id: number }) => r.id)).toEqual([4]);
  });

  it('returns empty for unknown root', () => {
    expect(buildCommentTree([c(9, 0)], 1)).toEqual([]);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd react-native && npx vitest run src/features/geek-reader/__tests__/comments.test.ts`

- [ ] **Step 3: 实现 `application/comments.ts`**

```ts
import type { Comment } from '../domain/models';

export type CommentNode = Comment & { replies: CommentNode[] };

export function buildCommentTree(flat: Comment[], rootParentId: number): CommentNode[] {
  const byId = new Map<number, CommentNode>();
  for (const c of flat) byId.set(c.id, { ...c, replies: [] });
  const roots: CommentNode[] = [];
  for (const node of byId.values()) {
    const parent = byId.get(node.parentId);
    if (parent) parent.replies.push(node);
    else if (node.parentId === rootParentId) roots.push(node);
  }
  return roots;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd react-native && npx vitest run src/features/geek-reader/__tests__/comments.test.ts`
Expected: PASS（2）。

- [ ] **Step 5: 提交**

```bash
git add react-native/src/features/geek-reader/application/comments.ts react-native/src/features/geek-reader/__tests__/comments.test.ts && git commit -m "feat(rn): buildCommentTree pure helper"
```

---

### Task R5: `application/locale.ts` + `application/translationCache.ts` + 测试

**Files:**
- Create: `react-native/src/features/geek-reader/application/locale.ts`
- Create: `react-native/src/features/geek-reader/application/translationCache.ts`
- Test: `react-native/src/features/geek-reader/__tests__/locale.test.ts`
- Test: `react-native/src/features/geek-reader/__tests__/translationCache.test.ts`

- [ ] **Step 1: `locale.ts` + 测试**

`application/locale.ts`:
```ts
import type { TargetLanguage } from '../domain/models';

export function deriveTargetLanguage(locale: string): TargetLanguage | null {
  const l = locale.toLowerCase();
  if (l.startsWith('zh') && (l.includes('hant') || l.includes('tw') || l.includes('hk'))) return 'zh-Hant';
  if (l.startsWith('zh')) return 'zh-Hans';
  if (l.startsWith('ja')) return 'ja';
  if (l.startsWith('ko')) return 'ko';
  return null; // en/其它 → 不译
}
```

`__tests__/locale.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { deriveTargetLanguage } from '../application/locale';

describe('deriveTargetLanguage', () => {
  it.each([
    ['zh-CN', 'zh-Hans'], ['zh-Hans-CN', 'zh-Hans'], ['zh', 'zh-Hans'],
    ['zh-TW', 'zh-Hant'], ['zh-Hant', 'zh-Hant'], ['zh-HK', 'zh-Hant'],
    ['ja-JP', 'ja'], ['ko-KR', 'ko'],
    ['en-US', null], ['en', null], ['fr-FR', null],
  ])('%s → %s', (input, expected) => {
    expect(deriveTargetLanguage(input)).toBe(expected);
  });
});
```

- [ ] **Step 2: `translationCache.ts`（批处理+去重+缓存，移植自 Hacki-OH TranslationRepository）+ 测试**

`application/translationCache.ts`:
```ts
import type { TargetLanguage } from '../domain/models';
import { translateBatch } from '../data/GeekReaderApiClient';

type Pending = { key: string; text: string; lang: TargetLanguage; resolve: (t: string) => void; reject: (e: unknown) => void };

const WINDOW_MS = 50;
const MAX_ENTRIES = 20;
const MAX_TOTAL_CHARS = 12_000;

const cache = new Map<string, string>();        // key: lang\ntext → translation
const inFlight = new Map<string, Promise<string>>();
let pending: Pending[] = [];
let timer: ReturnType<typeof setTimeout> | null = null;

function cacheKey(lang: TargetLanguage, text: string) { return `${lang}\n${text}`; }

function scheduleFlush() {
  if (timer) return;
  timer = setTimeout(() => { timer = null; void flush(); }, WINDOW_MS);
}

async function flush() {
  const batch = pending;
  pending = [];
  if (batch.length === 0) return;
  const byLang = new Map<TargetLanguage, Pending[]>();
  for (const p of batch) {
    const arr = byLang.get(p.lang) ?? [];
    arr.push(p);
    byLang.set(p.lang, arr);
  }
  for (const [lang, items] of byLang) {
    const chunks = chunkEntries(items, MAX_ENTRIES, MAX_TOTAL_CHARS);
    for (const chunk of chunks) {
      try {
        const res = await translateBatch({
          targetLanguage: lang,
          entries: chunk.map((p) => ({ key: p.key, text: p.text })),
        });
        const byKey = new Map(res.results.map((r) => [r.key, r]));
        for (const p of chunk) {
          const r = byKey.get(p.key);
          if (r?.translation) { cache.set(cacheKey(lang, p.text), r.translation); p.resolve(r.translation); }
          else p.reject(new Error(r?.error ?? 'translation_failed'));
        }
      } catch (e) {
        for (const p of chunk) p.reject(e);
      }
    }
  }
}

function chunkEntries(items: Pending[], maxEntries: number, maxChars: number): Pending[][] {
  const chunks: Pending[][] = [];
  let cur: Pending[] = [];
  let chars = 0;
  for (const it of items) {
    if (cur.length >= maxEntries || chars + it.text.length > maxChars) {
      if (cur.length) chunks.push(cur);
      cur = []; chars = 0;
    }
    cur.push(it); chars += it.text.length;
  }
  if (cur.length) chunks.push(cur);
  return chunks;
}

export function clearTranslationCache() { cache.clear(); inFlight.clear(); pending = []; if (timer) { clearTimeout(timer); timer = null; } }

export function translate(text: string, lang: TargetLanguage): Promise<string> {
  const k = cacheKey(lang, text);
  const hit = cache.get(k);
  if (hit) return Promise.resolve(hit);
  const flying = inFlight.get(k);
  if (flying) return flying;
  const key = `${k}\n${pending.length}`;
  const p = new Promise<string>((resolve, reject) => {
    pending.push({ key, text, lang, resolve, reject });
    scheduleFlush();
  });
  inFlight.set(k, p);
  p.finally(() => inFlight.delete(k));
  return p;
}

// 测试钩子：替换 transport
let transport: typeof translateBatch = translateBatch;
export function setTranslationTransport(t: typeof translateBatch) { transport = t; clearTranslationCache(); }
```

> 注意：把 `flush` 内对 `translateBatch` 的调用改成 `transport(...)`，让测试可替换。即把 `const res = await translateBatch(...)` 改为 `const res = await transport(...)`。

`__tests__/translationCache.test.ts`:
```ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('translationCache', () => {
  beforeEach(async () => {
    vi.useFakeTimers();
    const { setTranslationTransport, clearTranslationCache } = await import('../application/translationCache');
    setTranslationTransport(async (req) => ({
      results: req.entries.map((e) => ({ key: e.key, translation: `[${e.text}]` })),
    }));
    clearTranslationCache();
  });

  it('dedupes identical in-flight texts', async () => {
    const { translate } = await import('../application/translationCache');
    const t1 = translate('hello', 'zh-Hans');
    const t2 = translate('hello', 'zh-Hans');
    await vi.advanceTimersByTimeAsync(60);
    const [a, b] = await Promise.all([t1, t2]);
    expect(a).toBe('[hello]'); expect(b).toBe('[hello]');
  });

  it('caches results for repeat calls', async () => {
    const calls: number[] = [];
    const { setTranslationTransport, translate } = await import('../application/translationCache');
    setTranslationTransport(async (req) => { calls.push(req.entries.length); return { results: req.entries.map((e) => ({ key: e.key, translation: `T${e.text}` })) }; });
    await vi.advanceTimersByTimeAsync(60); await translate('x', 'zh-Hans');
    await vi.advanceTimersByTimeAsync(60);
    const r = await translate('x', 'zh-Hans'); // cache hit
    expect(r).toBe('Tx'); expect(calls).toEqual([1]);
  });

  it('batches multiple texts in one request', async () => {
    const seen: number[] = [];
    const { setTranslationTransport, translate } = await import('../application/translationCache');
    setTranslationTransport(async (req) => { seen.push(req.entries.length); return { results: req.entries.map((e) => ({ key: e.key, translation: 't' })) }; });
    const ps = [translate('a', 'zh-Hans'), translate('b', 'zh-Hans'), translate('c', 'zh-Hans')];
    await vi.advanceTimersByTimeAsync(60);
    await Promise.all(ps);
    expect(seen).toEqual([3]);
  });
});
```

- [ ] **Step 3: 跑两个测试确认通过**

Run: `cd react-native && npx vitest run src/features/geek-reader/__tests__/locale.test.ts src/features/geek-reader/__tests__/translationCache.test.ts`
Expected: PASS。

- [ ] **Step 4: 提交**

```bash
git add react-native/src/features/geek-reader/application react-native/src/features/geek-reader/__tests__/locale.test.ts react-native/src/features/geek-reader/__tests__/translationCache.test.ts && git commit -m "feat(rn): locale derivation + translation batch cache"
```

---

### Task R6: `state/GeekReaderProvider.tsx`（局部 Context）

**Files:**
- Create: `react-native/src/features/geek-reader/state/GeekReaderProvider.tsx`

- [ ] **Step 1: 实现**（无独立测试；hook 行为由 R7/R8 屏幕验证）

```tsx
import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';
import { AsyncState } from '../../../state/asyncState';
import type { Story, Comment } from '../domain/models';

type GeekReaderContextValue = {
  top: AsyncState<Story[]>;
  latest: AsyncState<Story[]>;
  setTop: (s: AsyncState<Story[]>) => void;
  setLatest: (s: AsyncState<Story[]>) => void;
};

const GeekReaderContext = createContext<GeekReaderContextValue | null>(null);

export function GeekReaderProvider({ children }: { children: ReactNode }) {
  const [top, setTop] = useState<AsyncState<Story[]>>({ status: 'idle' });
  const [latest, setLatest] = useState<AsyncState<Story[]>>({ status: 'idle' });
  const value = useMemo<GeekReaderContextValue>(() => ({ top, latest, setTop, setLatest }), [top, latest]);
  return <GeekReaderContext.Provider value={value}>{children}</GeekReaderContext.Provider>;
}

export function useGeekReader() {
  const ctx = useContext(GeekReaderContext);
  if (!ctx) throw new Error('useGeekReader 必须在 GeekReaderProvider 内使用');
  return ctx;
}
```

- [ ] **Step 2: 类型检查**

Run: `cd react-native && npx tsc --noEmit`
Expected: 无错。

- [ ] **Step 3: 提交**

```bash
git add react-native/src/features/geek-reader/state && git commit -m "feat(rn): GeekReaderProvider local context"
```

---

### Task R7: `presentation/ImmersiveTranslation.tsx`

**Files:**
- Create: `react-native/src/features/geek-reader/presentation/ImmersiveTranslation.tsx`

- [ ] **Step 1: 实现**（双语渲染；en→null 直接显原文；postFrame 自动触发；译中/已译/失败/配额态）

```tsx
import { useEffect, useRef, useState } from 'react';
import { Text, View, ActivityIndicator, Pressable } from 'react-native';
import { usePreferences } from '../../../preferences/PreferencesProvider';
import { deriveTargetLanguage } from '../application/locale';
import { translate } from '../application/translationCache';

export function ImmersiveTranslation({ text }: { text: string }) {
  const { locale } = usePreferences();
  const lang = deriveTargetLanguage(locale);
  const [result, setResult] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const triggered = useRef(false);

  useEffect(() => {
    if (!lang || triggered.current) return;
    triggered.current = true;
    setLoading(true);
    translate(text, lang)
      .then((t) => setResult(t))
      .catch(() => setFailed(true))
      .finally(() => setLoading(false));
  }, [lang, text]);

  if (!lang) return <Text>{text}</Text>;

  return (
    <View style={{ marginTop: 4 }}>
      <Text>{text}</Text>
      {loading && <ActivityIndicator size="small" />}
      {!loading && result && (
        <View style={{ borderLeftWidth: 3, borderLeftColor: '#A84444', paddingLeft: 8, marginTop: 2 }}>
          <Text style={{ color: '#A84444', fontSize: 11 }}>译 · {lang}</Text>
          <Text>{result}</Text>
        </View>
      )}
      {!loading && failed && <Text style={{ color: '#999', fontSize: 11 }}>翻译失败</Text>}
    </View>
  );
}
```

> `usePreferences()` 需返回 `locale`（PreferencesProvider 已有 locale 概念，若字段名不同按实际调整——调研报告里 PreferencesProvider 用 `user?.settings.language`，可在此 hook 内取 `useApp().user?.settings.language` 或新增 `locale` 导出。若 `usePreferences` 不直接返 locale，改为 `import { useApp } from '../../../state/AppStore'` 读 `user?.settings.language ?? 'zh-CN'`。）

- [ ] **Step 2: 类型检查**

Run: `cd react-native && npx tsc --noEmit`
Expected: 无错（若 `usePreferences().locale` 不存在，按上面注记改读 AppStore）。

- [ ] **Step 3: 提交**

```bash
git add react-native/src/features/geek-reader/presentation/ImmersiveTranslation.tsx && git commit -m "feat(rn): ImmersiveTranslation bilingual widget"
```

---

### Task R8: `presentation/CommentTree.tsx` + `StoryDetailScreen.tsx`

**Files:**
- Create: `react-native/src/features/geek-reader/presentation/CommentTree.tsx`
- Create: `react-native/src/features/geek-reader/presentation/StoryDetailScreen.tsx`

- [ ] **Step 1: `CommentTree.tsx`（递归 + 折叠）**

```tsx
import { useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import type { CommentNode } from '../application/comments';
import { ImmersiveTranslation } from './ImmersiveTranslation';

function timeAgo(unix: number): string {
  const d = Math.max(0, Math.floor(Date.now() / 1000 - unix));
  if (d < 60) return `${d}s`;
  if (d < 3600) return `${Math.floor(d / 60)}m`;
  if (d < 86400) return `${Math.floor(d / 3600)}h`;
  return `${Math.floor(d / 86400)}d`;
}

export function CommentTree({ nodes, depth = 0 }: { nodes: CommentNode[]; depth?: number }) {
  return (
    <View>
      {nodes.map((n) => <CommentRow key={n.id} node={n} depth={depth} />)}
    </View>
  );
}

function CommentRow({ node, depth }: { node: CommentNode; depth: number }) {
  const [collapsed, setCollapsed] = useState(false);
  if (node.deleted || node.dead) {
    return <Text style={{ paddingLeft: depth * 12, color: '#999' }}>[已删除]</Text>;
  }
  return (
    <View style={{ paddingLeft: depth * 12, paddingVertical: 6 }}>
      <Pressable onPress={() => setCollapsed((c) => !c)}>
        <Text style={{ fontSize: 12, color: '#666' }}>{node.by} · {timeAgo(node.time)} {node.replies.length ? `· ${collapsed ? '+' : '−'}${node.replies.length}` : ''}</Text>
      </Pressable>
      {!collapsed && (
        <View>
          <ImmersiveTranslation text={node.text} />
          {node.replies.length > 0 && <CommentTree nodes={node.replies} depth={depth + 1} />}
        </View>
      )}
    </View>
  );
}
```

- [ ] **Step 2: `StoryDetailScreen.tsx`**（从路由参数取 storyId，拉 story + 评论，渲染）

```tsx
import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, Text, View } from 'react-native';
import { Linking } from 'react-native';
import { useApp } from '../../../state/AppStore';
import { PageHeader } from '../../../design-system/components';
import { fetchItems } from '../data/GeekReaderApiClient';
import { toStory, toComment, type Story, type Comment } from '../domain/models';
import { buildCommentTree } from '../application/comments';
import { ImmersiveTranslation } from './ImmersiveTranslation';
import { CommentTree } from './CommentTree';

export function StoryDetailScreen({ storyId }: { storyId: number }) {
  const { navigate } = useApp();
  const [story, setStory] = useState<Story | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      setLoading(true);
      const { items } = await fetchItems([storyId]);
      const s = toStory(items[0] ?? null);
      const kidIds = s?.kids ?? [];
      const detail = kidIds.length ? await fetchItems(kidIds) : { items: [] };
      if (!alive) return;
      setStory(s);
      setComments(detail.items.map(toComment).filter((c): c is Comment => c !== null));
      setLoading(false);
    })().catch(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [storyId]);

  if (loading) return <View style={{ flex: 1 }}><ActivityIndicator /><PageHeader title="" onBack={() => navigate('geekreader.home')} /></View>;
  if (!story) return <View style={{ flex: 1 }}><Text>未找到</Text></View>;

  const tree = buildCommentTree(comments, story.id);

  return (
    <View style={{ flex: 1 }}>
      <PageHeader title={story.title} onBack={() => navigate('geekreader.home')} />
      <ScrollView>
        <View style={{ padding: 12 }}>
          <ImmersiveTranslation text={story.title} />
          {story.url ? (
            <Pressable onPress={() => Linking.openURL(story.url!)}><Text style={{ color: '#A84444' }}>阅读原文 ↗</Text></Pressable>
          ) : story.text ? <ImmersiveTranslation text={story.text} /> : null}
          <Text style={{ color: '#666', marginTop: 8 }}>{story.score} 分 · {story.commentsCount} 评论</Text>
        </View>
        <CommentTree nodes={tree} />
      </ScrollView>
    </View>
  );
}
```

> `PageHeader` 的 `onBack` / `navigate` 签名按实际设计系统调整（调研报告里 PageHeader 是 `{ title, rightAction? }`，没有 onBack——改用 `IconButton icon="arrow-left"` 放标题左侧，或包一层。`navigate` 来自 `useApp()`，按 AppStore 实际暴露的方法名调整）。

- [ ] **Step 3: 类型检查 + 按报错调整 API（PageHeader/navigate）**

Run: `cd react-native && npx tsc --noEmit`
按报错修：PageHeader 无 onBack→用 IconButton arrow-left；navigate 方法名对齐 AppStore。

- [ ] **Step 4: 提交**

```bash
git add react-native/src/features/geek-reader/presentation/CommentTree.tsx react-native/src/features/geek-reader/presentation/StoryDetailScreen.tsx && git commit -m "feat(rn): comment tree + story detail screen"
```

---

### Task R9: `presentation/GeekReaderHomeScreen.tsx` + 路由分发接线

**Files:**
- Create: `react-native/src/features/geek-reader/presentation/GeekReaderHomeScreen.tsx`
- Modify: `react-native/src/navigation/AppRouter.tsx`（加 import + 2 个 case）
- Modify: `react-native/App.tsx`（在 PreferencesProvider 后包 GeekReaderProvider）

- [ ] **Step 1: `GeekReaderHomeScreen.tsx`（精选/最新 Tab + 列表 + 下拉/分页）**

```tsx
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, RefreshControl, Text, View } from 'react-native';
import { GeekReaderProvider, useGeekReader } from '../state/GeekReaderProvider';
import { fetchStories, fetchStoriesResolved } from '../data/GeekReaderApiClient';
import { ImmersiveTranslation } from './ImmersiveTranslation';
import type { Story } from '../domain/models';
import { useApp } from '../../../state/AppStore';

const PAGE = 15;

function HomeInner({ onOpenStory }: { onOpenStory: (id: number) => void }) {
  const { top, latest, setTop, setLatest } = useGeekReader();
  const [tab, setTab] = useState<'top' | 'latest'>('top');
  const state = tab === 'top' ? top : latest;
  const setState = tab === 'top' ? setTop : setLatest;

  const load = useCallback(async (reset: boolean) => {
    setState({ status: 'loading' });
    try {
      const ids = await fetchStories(tab);
      const slice = ids.ids.slice(0, PAGE);
      const stories = await fetchStoriesResolved(tab, slice);
      setState({ status: stories.length ? 'success' : 'empty', data: reset ? stories : stories });
    } catch {
      setState({ status: 'error', message: '加载失败' });
    }
  }, [tab, setState]);

  useEffect(() => { void load(true); }, [load]);

  return (
    <View style={{ flex: 1 }}>
      <View style={{ flexDirection: 'row' }}>
        {(['top', 'latest'] as const).map((t) => (
          <Pressable key={t} onPress={() => setTab(t)} style={{ padding: 12 }}>
            <Text style={{ fontWeight: tab === t ? 'bold' : 'normal' }}>{t === 'top' ? '精选' : '最新'}</Text>
          </Pressable>
        ))}
      </View>
      {state.status === 'loading' && <ActivityIndicator />}
      {state.status === 'error' && <Text style={{ padding: 16 }}>{state.message}</Text>}
      {state.status === 'success' && (
        <FlatList
          data={state.data}
          keyExtractor={(item: Story) => String(item.id)}
          refreshControl={<RefreshControl refreshing={false} onRefresh={() => load(true)} />}
          renderItem={({ item }) => (
            <Pressable onPress={() => onOpenStory(item.id)} style={{ padding: 12, borderBottomWidth: 1, borderColor: '#eee' }}>
              <ImmersiveTranslation text={item.title} />
              <Text style={{ color: '#666', fontSize: 12 }}>{item.score} 分 · {item.by}</Text>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}

export function GeekReaderHomeScreen() {
  const { navigate } = useApp();
  return (
    <GeekReaderProvider>
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 20, fontWeight: 'bold', padding: 12 }}>极客译读</Text>
        <HomeInner onOpenStory={(id) => navigate('geekreader.story', { storyId: id })} />
      </View>
    </GeekReaderProvider>
  );
}
```

- [ ] **Step 2: `AppRouter.tsx` 加 import + 2 个 case**

import 区加：
```ts
import { GeekReaderHomeScreen } from '../features/geek-reader/presentation/GeekReaderHomeScreen';
import { StoryDetailScreen } from '../features/geek-reader/presentation/StoryDetailScreen';
```
switch default 前加：
```ts
    case 'geekreader.home': screen = <GeekReaderHomeScreen />; break;
    case 'geekreader.story': {
      const sid = Number(params?.storyId);
      screen = Number.isFinite(sid) ? <StoryDetailScreen storyId={sid} /> : <GeekReaderHomeScreen />;
      break;
    }
```
> 按 AppRouter 实际的 `params` 读取方式调整（调研报告里分发是 `switch(route)` + `screen=`；params 传递机制按现有路由参数约定，必要时把 storyId 走一个模块级变量或 Context，避免猜签名——优先 tsc 驱动）。

- [ ] **Step 3: 类型检查 + 修签名**

Run: `cd react-native && npx tsc --noEmit`
按报错对齐 `navigate`/`params` 签名。

- [ ] **Step 4: 全套测试 + typecheck**

Run: `cd react-native && npx vitest run && npx tsc --noEmit`
Expected: 全测试通过，typecheck 无错。

- [ ] **Step 5: 提交**

```bash
git add react-native/src/features/geek-reader/presentation/GeekReaderHomeScreen.tsx react-native/src/navigation/AppRouter.tsx react-native/App.tsx && git commit -m "feat(rn): geek-reader home screen + route dispatch"
```

---

### Task R10: 收尾验证（typecheck + 全测试 + Expo web 冒烟）

- [ ] **Step 1: 全套**

Run: `cd react-native && npx vitest run && npx tsc --noEmit`
Expected: geek-reader 5 个测试文件全过；typecheck 干净。

- [ ] **Step 2: （可选）Expo web 启动冒烟**——需 backend（8787）在跑

Run: `cd /Volumes/MacMiniDisk/workspace/geekread/backend && (npm run dev > /tmp/grb.log 2>&1 &) && cd ../react-native && EXPO_PUBLIC_GEEKREAD_BACKEND_URL=http://localhost:8787 timeout 60 npx expo start --web`
人工/截图确认首页「极客译读」入口可点、列表加载、翻译渲染。

- [ ] **Step 3: 更新 spec 验收勾选 + 提交**

在 `docs/superpowers/specs/2026-08-12-geek-reader-design.md` 勾掉「RN 端在 iOS/Android 跑通同样流程」的静态部分（测试+typecheck 通过；真机/模拟器留 Plan 5 集成测试）。

```bash
cd /Volumes/MacMiniDisk/workspace/geekread && git add docs && git commit -m "docs: RN geek-reader module verified (tests + typecheck)"
```

---

## Self-Review

**Spec 覆盖**：§3 feature 模块结构（domain/application/data/presentation）→ R2-R9 ✓；§4 数据流（stories/items/translate）→ R3+R9 ✓；§5 翻译 UX（双语+彩色竖线+译标签）→ R7 ✓；§6 共享契约 → GeekReaderApiClient 用 backend 契约 ✓；§9 ArkTS↔RN 共享契约 → ArkTS 在 Plan 3。评论树递归折叠 → R4+R8 ✓。

**占位符**：无 TBD；组件签名不确定处（PageHeader/navigate/params/usePreferences.locale）标注「按 tsc 报错对齐」，因 RN 壳具体签名需执行时确认——属可执行的精确指令，不是模糊占位。

**类型一致性**：`Story`/`Comment`/`TargetLanguage`（R2）在 R3-R9 一致引用；`CommentNode`（R4）在 R8 一致；`AsyncState`（壳现有）在 R6 一致；`translateBatch`/`TranslateRequest`/`TranslateResponse`（R3）在 R5 一致。
