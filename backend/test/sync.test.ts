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
    vi.stubEnv('NODE_ENV', 'test');
    delete process.env.HACKER_NEWS_API_URL;
    const { hnHealth } = await import('../lib/hn-health.js');
    hnHealth.reset();
  });
  afterEach(() => vi.restoreAllMocks());

  it('warmLists 拉 Algolia search 列表并保存', async () => {
    const spy = mockFetch({
      '/search?tags=front_page&hitsPerPage=50': { hits: [{ objectID: '1' }, { objectID: '2' }] },
      '/search_by_date?tags=story&hitsPerPage=50': { hits: [{ objectID: '3' }] },
    });
    const { warmLists } = await import('../lib/sync.js');
    const { readStoryList } = await import('../lib/hn-store.js');
    const r = await warmLists();
    expect(r).toEqual({ top: 2, latest: 1 });
    expect((await readStoryList('top'))?.ids).toEqual([1, 2]);
    expect(spy).toHaveBeenCalledTimes(2);
  });

  it('warmStoryHeaders upsert 文章头并返回 descendants 增长的 id 集合', async () => {
    const { upsertItems, __testBackdateItem } = await import('../lib/hn-store.js');
    await upsertItems([{ id: 1, raw: { id: 1, type: 'story', descendants: 5 } }]);
    // 回拨超出 fresh 窗口（15min），warm 才会回源拉新头（fresh 条目跳过网络，正是增量语义）
    await __testBackdateItem(1, 20);
    const spy = mockFetch({
      '/items/1': { id: 1, type: 'story', num_comments: 9 },
      '/items/2': { id: 2, type: 'story', num_comments: 0 },
    });
    const { warmStoryHeaders } = await import('../lib/sync.js');
    const grown = await warmStoryHeaders([1, 2]);
    expect(grown).toEqual([1]); // 1 的 descendants 5→9 增长；2 是新入库不算增长
    const { readItems } = await import('../lib/hn-store.js');
    expect((await readItems([1])).get(1)?.raw).toMatchObject({ descendants: 9 });
    expect(spy).toHaveBeenCalledTimes(2);
  });

  it('warmTrees 受预算约束，整树一次拉取落库', async () => {
    mockFetch({
      '/items/1': {
        id: 1, type: 'story', title: 'S',
        children: [
          { id: 10, type: 'comment', parent_id: 1, text: 'c2', children: [] },
        ],
      },
    });
    const { warmTrees } = await import('../lib/sync.js');
    const n = await warmTrees([1], 5);
    expect(n).toBe(1);
    const { readItems } = await import('../lib/hn-store.js');
    // 整树拉取后评论 10 落库（text 来自 Algolia 嵌套树）
    expect((await readItems([10])).get(10)?.raw).toMatchObject({ text: 'c2' });
  });

  it('tick 串联三层并尊重预算（pullStoryList 落库完整 story）', async () => {
    mockFetch({
      '/search?tags=front_page&hitsPerPage=50': {
        hits: [{ objectID: '1', title: 't', author: 'a', num_comments: 5, children: [10] }],
      },
      '/search_by_date?tags=story&hitsPerPage=50': { hits: [] },
    });
    const { tick } = await import('../lib/sync.js');
    const { readStoryList, readItems } = await import('../lib/hn-store.js');
    const r = await tick();
    expect(r).toMatchObject({ lists: { top: 1, latest: 0 } });
    expect((await readStoryList('top'))?.ids).toEqual([1]);
    // 列表层已把完整 story 对象落库（children→kids、num_comments→descendants）
    expect((await readItems([1])).get(1)?.raw).toMatchObject({ title: 't', descendants: 5, kids: [10] });
  });

  it('上游全挂时 tick 不抛（降级语义，下个 tick 再试）', async () => {
    mockFetch({});
    const { tick } = await import('../lib/sync.js');
    const r = await tick();
    expect(r.errors).toBeGreaterThan(0);
  });
});
