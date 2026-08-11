import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function mockFetch(map: Record<string, unknown>) {
  const spy = vi.fn(async (url: string | URL | Request) => {
    const path = String(typeof url === 'string' ? url : url.toString());
    const entry = Object.entries(map).find(([key]) => path.endsWith(key));
    if (!entry) return new Response('not found', { status: 502 });
    return new Response(JSON.stringify(entry[1]), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  });
  globalThis.fetch = spy as unknown as typeof fetch;
  return spy;
}

describe('hacker-news', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.REDIS_URL;
    delete process.env.HACKER_NEWS_API_URL;
  });
  afterEach(() => vi.restoreAllMocks());

  it('fetchStoryIds top returns integer ids', async () => {
    mockFetch({ '/topstories.json': [3, 2, 1] });
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
    const { setJsonCache } = await import('../lib/storage.js');
    const first = await fetchItems([9]);
    expect(first.items[0]).toEqual({ id: 9, title: 'cached' });
    // Force the cached entry past its fresh window so fetchItem must retry upstream.
    await setJsonCache('hn:item:9', { id: 9, title: 'cached' }, 0, 3600);
    mockFetch({});
    const second = await fetchItems([9]);
    expect(second.items[0]).toEqual({ id: 9, title: 'cached' });
    expect(second.stale).toBe(true);
  });
});
