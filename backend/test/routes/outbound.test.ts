import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function resetEnv() {
  vi.resetModules();
  delete process.env.DATABASE_URL;
  delete process.env.MODERATION_MODE;
  delete process.env.MODERATION_HTTP_URL;
  delete process.env.OUTBOUND_FILTER;
}

describe('出站内容过滤（stories / items / tree）', () => {
  beforeEach(resetEnv);
  afterEach(() => vi.restoreAllMocks());

  it('stories：命中词库的条目不下发', async () => {
    globalThis.fetch = vi.fn(async () => new Response(JSON.stringify({
      hits: [
        { objectID: '7', title: 'Show HN: a small database', author: 'x' },
        { objectID: '8', title: '专业代开发票 快速办理', author: 'y' },
      ],
    }), { status: 200 })) as unknown as typeof fetch;
    const { GET } = await import('../../app/api/reader/stories/route.js');
    const body = await (await GET(new Request('http://localhost/api/reader/stories?type=top'))).json();
    expect(body.items.map((item: { id: number }) => item.id)).toEqual([7]);
    expect(body.blocked).toBe(1);
  });

  it('items：被下架的评论以 null 占位（顺序不变）', async () => {
    const { addBlock } = await import('../../lib/blocklist.js');
    await addBlock({ kind: 'comment', targetId: 22, reason: 'manual' });
    globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
      const id = Number(String(url).match(/items\/(\d+)/)?.[1]);
      return new Response(JSON.stringify({ id, type: 'comment', parent_id: 1, text: `comment ${id}`, author: 'a' }), { status: 200 });
    }) as unknown as typeof fetch;
    const { POST } = await import('../../app/api/reader/items/route.js');
    const body = await (await POST(new Request('http://localhost/api/reader/items', {
      method: 'POST',
      body: JSON.stringify({ ids: [21, 22] }),
    }))).json();
    expect(body.items).toHaveLength(2);
    expect(body.items[0]).toMatchObject({ id: 21 });
    expect(body.items[1]).toBeNull();
    expect(body.blocked).toBe(1);
  });

  it('tree：命中词库/黑名单的评论不下发，story 被拉黑时返回空树', async () => {
    globalThis.fetch = vi.fn(async () => new Response(JSON.stringify({
      id: 1,
      type: 'story',
      title: 'story',
      children: [
        { id: 2, type: 'comment', parent_id: 1, text: '正常评论', children: [] },
        { id: 3, type: 'comment', parent_id: 1, text: '网络赌博 推广链接', children: [] },
      ],
    }), { status: 200 })) as unknown as typeof fetch;
    const { POST } = await import('../../app/api/reader/tree/route.js');
    const body = await (await POST(new Request('http://localhost/api/reader/tree', {
      method: 'POST',
      body: JSON.stringify({ storyId: 1 }),
    }))).json();
    expect(body.items.map((item: { id: number }) => item.id)).toEqual([2]);
    expect(body.blocked).toBe(1);

    // story 被拉黑 → 空树 + blocked，且不再请求上游
    const { addBlock } = await import('../../lib/blocklist.js');
    await addBlock({ kind: 'story', targetId: 1, reason: 'manual' });
    const spy = vi.fn();
    globalThis.fetch = spy as unknown as typeof fetch;
    const blockedBody = await (await POST(new Request('http://localhost/api/reader/tree', {
      method: 'POST',
      body: JSON.stringify({ storyId: 1 }),
    }))).json();
    expect(blockedBody).toMatchObject({ items: [], blocked: true });
    expect(spy).not.toHaveBeenCalled();
  });
});