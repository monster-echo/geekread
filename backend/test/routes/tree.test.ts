import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/** 模拟 Algolia /items/{id}：按 id 返回 map 里的条目（含嵌套 children）。 */
function hnFetch(map: Record<number, unknown>) {
  return vi.fn(async (_url: unknown) => {
    const url = String(_url);
    const id = Number(url.match(/items\/(\d+)/)?.[1]);
    const item = map[id] ?? null;
    return new Response(JSON.stringify(item), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  }) as unknown as typeof fetch;
}

describe('POST /api/reader/tree', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.REDIS_URL;
    delete process.env.DATABASE_URL;
  });
  afterEach(() => vi.restoreAllMocks());

  it('resolves the whole comment tree from a single nested fetch', async () => {
    const map: Record<number, unknown> = {
      1: {
        id: 1, type: 'story', title: 'S',
        children: [
          { id: 2, type: 'comment', parent_id: 1, text: 'c2', children: [{ id: 4, type: 'comment', parent_id: 2, text: 'c4', children: [] }] },
          { id: 3, type: 'comment', parent_id: 1, text: 'c3', children: [] },
        ],
      },
    };
    globalThis.fetch = hnFetch(map);
    const { POST } = await import('../../app/api/reader/tree/route.js');
    const res = await POST(new Request('http://x/api/reader/tree', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ storyId: 1 }),
    }));
    const body = await res.json();
    expect(res.status).toBe(200);
    const ids = body.items.map((i: { id: number }) => i.id).sort((a: number, b: number) => a - b);
    expect(ids).toEqual([2, 3, 4]);
  });

  it('400 when storyId missing or invalid', async () => {
    const { POST } = await import('../../app/api/reader/tree/route.js');
    const res = await POST(new Request('http://x/api/reader/tree', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({}),
    }));
    expect(res.status).toBe(400);
  });
});
