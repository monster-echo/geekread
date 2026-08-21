import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('POST /api/reader/items', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.REDIS_URL;
  });
  afterEach(() => vi.restoreAllMocks());

  it('returns items in order', async () => {
    globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
      const path = String(url);
      if (path.endsWith('/items/1')) return new Response(JSON.stringify({ id: 1, type: 'story', title: 'a', author: 'x' }), { status: 200 });
      if (path.endsWith('/items/2')) return new Response(JSON.stringify({ id: 2, type: 'story', title: 'b', author: 'y' }), { status: 200 });
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
