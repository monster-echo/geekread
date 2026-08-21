// backend/lib/hacker-news.ts
import './proxy';
import { readItems, readStoryList, saveStoryList, upsertItems } from './hn-store';
import { hnHealth } from './hn-health';

// HN 数据源已切到 Algolia 官方 API：search 一次返回完整 story 对象（含 children），
// 消除 Firebase 的「列表→逐条 /item」N+1 拉取，且无需代理、延迟极低（processingTimeMS≈1）。
const defaultBaseUrl = 'https://hn.algolia.com/api/v1';
const listFreshSeconds = 180;      // 列表 fresh 3min
const listStaleSeconds = 1200;     // 超 20min 同步刷新一次
export const ITEM_FRESH_SECONDS = 900;      // 条目 fresh 15min
const fetchTimeoutMs = 8_000;
const fetchConcurrency = 20;
/** 首页一次拉满的 story 数：够无限滚动，客户端无需第二跳分页。 */
const READER_LIST_SIZE = 100;

export type HackerNewsItem = Record<string, unknown>;

function baseUrl(): string {
  return (process.env.HACKER_NEWS_API_URL?.trim() || defaultBaseUrl).replace(/\/$/, '');
}

/** 上游拉取：单源（默认 Algolia），埋点 hn-health（T8）。 */
async function fetchJson<T>(path: string): Promise<T> {
  const base = baseUrl();
  let response: Response;
  try {
    response = await fetch(`${base}${path}`, {
      signal: AbortSignal.timeout(fetchTimeoutMs),
      headers: { accept: 'application/json' },
    });
  } catch (error) {
    hnHealth.noteRequest(false); // 超时/网络错误
    const msg = error instanceof Error ? error.message : 'hacker_news_unavailable';
    console.warn(`[geekread] HN fetch failed via ${base}: ${msg}`);
    throw error instanceof Error ? error : new Error(msg);
  }
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
}

function isValidItem(value: unknown): value is HackerNewsItem {
  return typeof value === 'object' && !Array.isArray(value) && value !== null;
}

/**
 * 把 Algolia 的 children 归一化为 Firebase 风格的 kids（number[]）。
 * search hit 的 children 是 number[]；/items/{id} 的 children 是嵌套完整对象[]。
 */
function extractKids(children: unknown): number[] {
  if (!Array.isArray(children)) return [];
  return children
    .map((c) =>
      typeof c === 'number'
        ? c
        : c !== null && typeof c === 'object'
          ? Number((c as Record<string, unknown>).id ?? (c as Record<string, unknown>).objectID)
          : NaN,
    )
    .filter((n) => Number.isSafeInteger(n) && n > 0);
}

/**
 * Algolia 响应 → 归一化为 Firebase 形状的 HackerNewsItem，
 * 使下游 hn-store.rowFields / 客户端 toStory / toComment / tree BFS 无需改动。
 */
export function mapItem(raw: unknown): HackerNewsItem | null {
  if (raw === null) return null;
  if (typeof raw !== 'object' || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;

  const id = Number(r.id ?? r.objectID);
  if (!Number.isSafeInteger(id) || id <= 0) return null;

  const type = typeof r.type === 'string' ? r.type : (r.parent_id != null ? 'comment' : 'story');
  const isStory = type === 'story';
  const kids = extractKids(r.children);

  const out: HackerNewsItem = { id, type };
  const by = typeof r.author === 'string' && r.author.length > 0 ? r.author : undefined;
  if (by) out.by = by;
  const time = typeof r.created_at_i === 'number' && Number.isSafeInteger(r.created_at_i) ? r.created_at_i : undefined;
  if (time !== undefined) out.time = time;
  if (typeof r.title === 'string' && r.title.length > 0) out.title = r.title;
  if (typeof r.url === 'string' && r.url.length > 0) out.url = r.url;
  const text = [r.story_text, r.comment_text, r.text].find((v) => typeof v === 'string' && v.length > 0);
  if (text) out.text = text;
  const score = typeof r.points === 'number' && Number.isSafeInteger(r.points) ? r.points : undefined;
  if (score !== undefined) out.score = score;
  // story 根节点（/items/{id}）无 num_comments，用 children.length 兜底；评论无 descendants。
  const descendants = (typeof r.num_comments === 'number' && Number.isSafeInteger(r.num_comments))
    ? r.num_comments
    : (isStory ? kids.length : undefined);
  if (descendants !== undefined) out.descendants = descendants;
  if (kids.length > 0) out.kids = kids;
  if (r.parent_id != null) {
    const p = Number(r.parent_id);
    if (Number.isSafeInteger(p)) out.parent = p;
  }
  if (by === undefined && text === undefined) out.deleted = true;
  return out;
}

/** 列表层低层：拉 Algolia search → 归一化 → 落库（storyList + 完整对象），返回 { ids, items }。 */
export async function pullStoryList(type: 'top' | 'latest', limit: number): Promise<{
  ids: number[];
  items: HackerNewsItem[];
}> {
  const query = type === 'top'
    ? `/search?tags=front_page&hitsPerPage=${limit}`
    : `/search_by_date?tags=story&hitsPerPage=${limit}`;
  const data = await fetchJson<{ hits?: unknown[] }>(query);
  if (data === null || typeof data !== 'object' || !Array.isArray(data.hits)) {
    throw new Error('hacker_news_invalid_response');
  }
  const hits = data.hits;
  const items: HackerNewsItem[] = [];
  const ids: number[] = [];
  for (const hit of hits) {
    const mapped = mapItem(hit);
    if (mapped === null) continue;
    items.push(mapped);
    ids.push(Number(mapped.id));
  }
  await saveStoryList(type, ids);
  await upsertItems(items.map((it) => ({ id: Number(it.id), raw: it })));
  return { ids, items };
}

/** 单条回源（无 SWR 检查）：/items/{id} + 归一化，供 resolveItem / 后台刷新 / sync 复用。 */
export async function fetchItemRaw(id: number): Promise<HackerNewsItem | null> {
  const raw = await fetchJson<unknown>(`/items/${id}`);
  return mapItem(raw);
}

/** 首页 story 列表（完整对象，单跳）。SWR 语义与旧 fetchStoryIds 一致。 */
export async function fetchStories(type: 'top' | 'latest'): Promise<{
  items: HackerNewsItem[];
  cached: boolean;
  stale: boolean;
}> {
  const stored = await readStoryList(type);
  const ageSeconds = stored ? (Date.now() - stored.fetchedAt.getTime()) / 1000 : Infinity;

  // fresh：直接返回缓存条目（完整对象已在 hnItem）
  if (stored && ageSeconds <= listFreshSeconds) {
    return { items: await resolveCachedItems(stored.ids), cached: true, stale: false };
  }
  // stale 窗口内：返回旧值 + 后台刷新
  if (stored && ageSeconds <= listStaleSeconds) {
    pullStoryList(type, READER_LIST_SIZE).catch(() => {});
    return { items: await resolveCachedItems(stored.ids), cached: true, stale: true };
  }
  // 无数据或超 stale：同步刷新一次，失败时有旧值返旧值
  try {
    const { items } = await pullStoryList(type, READER_LIST_SIZE);
    return { items, cached: false, stale: false };
  } catch (error) {
    if (stored) return { items: await resolveCachedItems(stored.ids), cached: true, stale: true };
    throw error;
  }
}

/** 按 ids 顺序从 hnItem 读回完整对象，丢弃已删除（raw 为 null）。 */
async function resolveCachedItems(ids: number[]): Promise<HackerNewsItem[]> {
  const rows = await readItems(ids);
  const out: HackerNewsItem[] = [];
  for (const id of ids) {
    const raw = rows.get(id)?.raw;
    if (raw !== null && raw !== undefined) out.push(raw);
  }
  return out;
}

type ItemOutcome = { item: HackerNewsItem | null; cached: boolean; stale: boolean };

async function resolveItem(id: number): Promise<ItemOutcome> {
  const rows = await readItems([id]);
  const hit = rows.get(id);
  if (hit) {
    const ageSeconds = (Date.now() - hit.fetchedAt.getTime()) / 1000;
    if (ageSeconds <= ITEM_FRESH_SECONDS) return { item: hit.raw, cached: true, stale: false };
    // 超 fresh：返回旧值 + 后台刷新（fire-and-forget）
    refreshItemInBackground(id).catch(() => {});
    return { item: hit.raw, cached: true, stale: true };
  }
  // 未落库（长尾）：回源一次并 upsert，此后永久本地
  const item = await fetchItemRaw(id);
  await upsertItems([{ id, raw: item }]);
  return { item, cached: false, stale: false };
}

// 后台刷新 in-flight 去重：同 id 并发刷新只发一次（防刷新风暴）
const refreshingItems = new Set<number>();

async function refreshItemInBackground(id: number): Promise<void> {
  if (refreshingItems.has(id)) return;
  refreshingItems.add(id);
  try {
    const item = await fetchItemRaw(id);
    if (item !== null) await upsertItems([{ id, raw: item }]);
  } catch {
    // 失败保留旧值
  } finally {
    refreshingItems.delete(id);
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

/** 评论树单次展开上限，对齐旧 tree 路由 MAX_COMMENTS。 */
const TREE_MAX_COMMENTS = 200;

/**
 * 整棵评论树：Algolia /items/{storyId} 一次返回完整嵌套树，递归展平为扁平评论列表，
 * 取代旧的逐层 BFS（每层一次 fetchItems，冷缓存下 N+1 次上游请求）。
 * SWR：story fresh → 纯读 hnItem 组装；stale → 返缓存 + 后台整树刷新；冷缓存 → 一次整树拉取。
 */
export async function fetchCommentTree(storyId: number): Promise<{
  items: HackerNewsItem[];
  cached: boolean;
  stale: boolean;
}> {
  const hit = (await readItems([storyId])).get(storyId);
  if (hit) {
    const ageSeconds = (Date.now() - hit.fetchedAt.getTime()) / 1000;
    const items = await assembleTreeFromCache(storyId);
    if (items !== null) {
      const stale = ageSeconds > ITEM_FRESH_SECONDS;
      if (stale) refreshTreeInBackground(storyId).catch(() => {});
      return { items, cached: true, stale };
    }
    // 缓存缺评论（未预热）→ 落入整树拉取
  }
  const items = (await pullTree(storyId)).slice(0, TREE_MAX_COMMENTS);
  return { items, cached: false, stale: false };
}

/** 从 hnItem 纯读组装整树（BFS 走缓存，无网络）；任一评论缺失返回 null 以回退整树拉取。 */
async function assembleTreeFromCache(storyId: number): Promise<HackerNewsItem[] | null> {
  const story = (await readItems([storyId])).get(storyId)?.raw;
  if (!story) return null;
  const all: HackerNewsItem[] = [];
  const seen = new Set<number>([storyId]);
  let frontier = extractKids((story as Record<string, unknown>).kids);
  while (frontier.length > 0 && all.length < TREE_MAX_COMMENTS) {
    const batch = frontier.splice(0, 50);
    const rows = await readItems(batch);
    for (const id of batch) {
      const raw = rows.get(id)?.raw;
      if (!raw) return null; // 缓存缺该评论 → 回退整树拉取
      if (seen.has(id)) continue;
      seen.add(id);
      all.push(raw);
      const kids = extractKids((raw as Record<string, unknown>).kids);
      for (const k of kids) if (!seen.has(k) && all.length < TREE_MAX_COMMENTS) frontier.push(k);
    }
  }
  return all;
}

/** 整树一次拉取：/items/{storyId} 返回嵌套 children，迭代展平 + 落库（story + 全部评论，不截断）。 */
export async function pullTree(storyId: number): Promise<HackerNewsItem[]> {
  const root = await fetchJson<unknown>(`/items/${storyId}`);
  const story = mapItem(root);
  const items: HackerNewsItem[] = [];
  const seen = new Set<number>([storyId]);
  const stack: unknown[] = root !== null && typeof root === 'object' && !Array.isArray(root) ? [root] : [];
  while (stack.length > 0) {
    const node = stack.pop();
    if (node === null || typeof node !== 'object' || Array.isArray(node)) continue;
    const children = (node as Record<string, unknown>).children;
    if (!Array.isArray(children)) continue;
    for (const child of children) {
      if (child === null || typeof child !== 'object' || Array.isArray(child)) continue;
      const mapped = mapItem(child);
      if (mapped === null) continue;
      const id = Number(mapped.id);
      if (seen.has(id)) continue;
      seen.add(id);
      items.push(mapped);
      stack.push(child);
    }
  }
  const toUpsert: { id: number; raw: HackerNewsItem | null }[] = [];
  if (story !== null) toUpsert.push({ id: Number(story.id), raw: story });
  for (const it of items) toUpsert.push({ id: Number(it.id), raw: it });
  if (toUpsert.length > 0) await upsertItems(toUpsert);
  return items;
}

// 后台整树刷新 in-flight 去重：同 storyId 并发刷新只发一次。
const refreshingTrees = new Set<number>();

async function refreshTreeInBackground(storyId: number): Promise<void> {
  if (refreshingTrees.has(storyId)) return;
  refreshingTrees.add(storyId);
  try {
    await pullTree(storyId);
  } catch {
    // 失败保留旧值
  } finally {
    refreshingTrees.delete(storyId);
  }
}
