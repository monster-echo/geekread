// backend/lib/hacker-news.ts
import './proxy';
import { readItems, readStoryList, saveStoryList, upsertItems } from './hn-store';
import { hnHealth } from './hn-health';

const defaultBaseUrl = 'https://hacker-news.firebaseio.com/v0';
const listFreshSeconds = 180;      // 列表 fresh 3min
const listStaleSeconds = 1200;     // 超 20min 同步刷新一次
export const ITEM_FRESH_SECONDS = 900;      // 条目 fresh 15min
const fetchTimeoutMs = 8_000;
const fetchConcurrency = 20;

export type HackerNewsItem = Record<string, unknown>;

function baseUrl(): string {
  return (process.env.HACKER_NEWS_API_URL?.trim() || defaultBaseUrl).replace(/\/$/, '');
}

/** 上游拉取：配置源优先，失败回退直连 Firebase。埋点 hn-health（T8）。 */
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

// 后台刷新 in-flight 去重：同 key 并发刷新只发一次（防刷新风暴）
const refreshingLists = new Set<string>();

async function refreshStoryListInBackground(type: 'top' | 'latest'): Promise<void> {
  if (refreshingLists.has(type)) return;
  refreshingLists.add(type);
  try {
    const path = type === 'top' ? '/topstories.json' : '/newstories.json';
    const ids = await fetchJson<number[]>(path);
    if (Array.isArray(ids) && ids.every((id) => Number.isInteger(id))) {
      await saveStoryList(type, ids);
    }
  } catch {
    // 后台刷新失败不影响用户（下次请求再用 stale）
  } finally {
    refreshingLists.delete(type);
  }
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
  const item = await fetchJson<unknown>(`/item/${id}.json`);
  if (!isValidItem(item)) throw new Error('hacker_news_invalid_response');
  await upsertItems([{ id, raw: item }]);
  return { item, cached: false, stale: false };
}

// 后台刷新 in-flight 去重：同 id 并发刷新只发一次（防刷新风暴）
const refreshingItems = new Set<number>();

async function refreshItemInBackground(id: number): Promise<void> {
  if (refreshingItems.has(id)) return;
  refreshingItems.add(id);
  try {
    const item = await fetchJson<unknown>(`/item/${id}.json`);
    if (isValidItem(item)) await upsertItems([{ id, raw: item }]);
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
