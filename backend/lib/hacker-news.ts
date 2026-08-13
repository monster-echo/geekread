import './proxy';
import { getJsonCache, setJsonCache } from './storage';

const defaultBaseUrl = 'https://hacker-news.firebaseio.com/v0';
const listFreshTtlSeconds = 60;
const listStaleTtlSeconds = 600;
const itemFreshTtlSeconds = 300;
const itemStaleTtlSeconds = 3600;
// HN 冷拉较慢：提高并发（20 一批拉完）并缩短超时（慢请求快速失败），
// 避免无缓存首次加载卡十几秒。
const fetchTimeoutMs = 8_000;
const fetchConcurrency = 20;

export type HackerNewsItem = Record<string, unknown>;

function baseUrl(): string {
  return (process.env.HACKER_NEWS_API_URL?.trim() || defaultBaseUrl).replace(/\/$/, '');
}

// 优先用配置的数据源（如 HACKER_NEWS_API_URL 指向 proxy.0x2a.top 加速），
// 失败自动回退直连 Firebase。
async function fetchJson<T>(path: string): Promise<T> {
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

export async function fetchStoryIds(type: 'top' | 'latest'): Promise<{
  ids: number[];
  cached: boolean;
  stale: boolean;
}> {
  const cacheKey = `hn:stories:${type}`;
  const cached = await getJsonCache<number[]>(cacheKey);
  if (cached && !cached.stale) return { ids: cached.value, cached: true, stale: false };

  try {
    const path = type === 'top' ? '/topstories.json' : '/newstories.json';
    const ids = await fetchJson<number[]>(path);
    if (!Array.isArray(ids) || ids.some((id) => !Number.isInteger(id))) {
      throw new Error('hacker_news_invalid_response');
    }
    await setJsonCache(cacheKey, ids, listFreshTtlSeconds, listStaleTtlSeconds);
    return { ids, cached: false, stale: false };
  } catch (error) {
    if (cached) return { ids: cached.value, cached: true, stale: true };
    throw error;
  }
}

async function fetchItem(id: number): Promise<{ item: HackerNewsItem | null; cached: boolean; stale: boolean }> {
  const cacheKey = `hn:item:${id}`;
  const cached = await getJsonCache<HackerNewsItem | null>(cacheKey);
  if (cached && !cached.stale) return { item: cached.value, cached: true, stale: false };

  try {
    const item = await fetchJson<HackerNewsItem | null>(`/item/${id}.json`);
    if (item !== null && (typeof item !== 'object' || Array.isArray(item))) {
      throw new Error('hacker_news_invalid_response');
    }
    await setJsonCache(cacheKey, item, itemFreshTtlSeconds, itemStaleTtlSeconds);
    return { item, cached: false, stale: false };
  } catch (error) {
    if (cached) return { item: cached.value, cached: true, stale: true };
    throw error;
  }
}

export async function fetchItems(ids: number[]): Promise<{
  items: Array<HackerNewsItem | null>;
  cached: boolean;
  stale: boolean;
}> {
  const uniqueIds = [...new Set(ids)];
  const results = new Map<number, Awaited<ReturnType<typeof fetchItem>>>();
  let nextIndex = 0;

  async function worker(): Promise<void> {
    while (nextIndex < uniqueIds.length) {
      const index = nextIndex++;
      const id = uniqueIds[index];
      if (id === undefined) return;
      results.set(id, await fetchItem(id));
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
