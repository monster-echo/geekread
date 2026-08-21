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
    delete process.env.DATABASE_URL;
    vi.stubEnv('NODE_ENV', 'test');
  });
  afterEach(() => vi.restoreAllMocks());

  it('fetchStories top returns mapped full stories (Algolia search)', async () => {
    mockFetch({
      '/search?tags=front_page&hitsPerPage=100': {
        hits: [
          { objectID: '3', title: 'three', author: 'a', points: 30, num_comments: 3, created_at_i: 100, children: [10, 11] },
          { objectID: '2', title: 'two', author: 'b', points: 20, num_comments: 0, created_at_i: 90 },
          { objectID: '1', title: 'one', author: 'c', points: 10, num_comments: 1, created_at_i: 80 },
        ],
      },
    });
    const { fetchStories } = await import('../lib/hacker-news.js');
    const r = await fetchStories('top');
    expect(r.items.map((x) => x.id)).toEqual([3, 2, 1]);
    expect(r.items[0]).toMatchObject({ title: 'three', by: 'a', score: 30, descendants: 3, kids: [10, 11] });
    expect(r.cached).toBe(false);
  });

  it('rejects malformed story list', async () => {
    mockFetch({ '/search?tags=front_page&hitsPerPage=100': { not: 'hits' } });
    const { fetchStories } = await import('../lib/hacker-news.js');
    await expect(fetchStories('top')).rejects.toThrow();
  });

  it('fetchItems batch-loads and preserves order (Algolia items)', async () => {
    mockFetch({
      '/items/1': { id: 1, type: 'story', title: 'a', author: 'x' },
      '/items/2': { id: 2, type: 'story', title: 'b', author: 'y' },
      '/items/3': null,
    });
    const { fetchItems } = await import('../lib/hacker-news.js');
    const r = await fetchItems([1, 2, 3]);
    expect(r.items.map((x) => x?.id)).toEqual([1, 2, undefined]);
  });

  it('serves stored items on upstream failure (stale)', async () => {
    mockFetch({ '/items/9': { id: 9, type: 'story', title: 'cached', author: 'x' } });
    const { fetchItems } = await import('../lib/hacker-news.js');
    const { __testBackdateItem } = await import('../lib/hn-store.js');
    const first = await fetchItems([9]);
    expect(first.items[0]).toMatchObject({ id: 9, title: 'cached' });
    // fetchedAt 回拨 2 小时 → 超过 item fresh 窗口，必须重试上游
    await __testBackdateItem(9, 120);
    mockFetch({});
    const second = await fetchItems([9]);
    expect(second.items[0]).toMatchObject({ id: 9, title: 'cached' });
    expect(second.stale).toBe(true);
  });

  it('fetchCommentTree flattens nested Algolia tree and caches it', async () => {
    mockFetch({
      '/items/1': {
        id: 1, type: 'story', title: 'S',
        children: [
          { id: 2, type: 'comment', parent_id: 1, text: 'c2', children: [{ id: 4, type: 'comment', parent_id: 2, text: 'c4', children: [] }] },
          { id: 3, type: 'comment', parent_id: 1, text: 'c3', children: [] },
        ],
      },
    });
    const { fetchCommentTree } = await import('../lib/hacker-news.js');
    const r = await fetchCommentTree(1);
    expect(r.items.map((x) => x.id).sort()).toEqual([2, 3, 4]);
    expect(r.cached).toBe(false);
  });

  it('fetchCommentTree serves fresh tree from cache without upstream', async () => {
    const { upsertItems } = await import('../lib/hn-store.js');
    await upsertItems([
      { id: 1, raw: { id: 1, type: 'story', title: 'S', kids: [2, 3] } },
      { id: 2, raw: { id: 2, type: 'comment', parent: 1, text: 'c2', kids: [4] } },
      { id: 3, raw: { id: 3, type: 'comment', parent: 1, text: 'c3', kids: [] } },
      { id: 4, raw: { id: 4, type: 'comment', parent: 2, text: 'c4', kids: [] } },
    ]);
    const spy = mockFetch({}); // 上游不应被调用
    const { fetchCommentTree } = await import('../lib/hacker-news.js');
    const r = await fetchCommentTree(1);
    expect(r.cached).toBe(true);
    expect(r.items.map((x) => x.id).sort()).toEqual([2, 3, 4]);
    expect(spy).not.toHaveBeenCalled();
  });
});
