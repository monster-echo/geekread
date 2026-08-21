import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('GET /api/reader/stories', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.REDIS_URL;
  });
  afterEach(() => vi.restoreAllMocks());

  it('returns top stories as full objects', async () => {
    globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
      const path = String(url);
      if (path.endsWith('/search?tags=front_page&hitsPerPage=100')) {
        return new Response(JSON.stringify({
          hits: [
            { objectID: '7', title: 'a', author: 'x' },
            { objectID: '8', title: 'b', author: 'y' },
          ],
        }), { status: 200 });
      }
      return new Response('nf', { status: 502 });
    }) as unknown as typeof fetch;
    const { GET } = await import('../../app/api/reader/stories/route.js');
    const res = await GET(new Request('http://localhost/api/reader/stories?type=top'));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.items.map((i: { id: number }) => i.id)).toEqual([7, 8]);
  });

  it('400 on bad type', async () => {
    const { GET } = await import('../../app/api/reader/stories/route.js');
    const res = await GET(new Request('http://localhost/api/reader/stories?type=hot'));
    expect(res.status).toBe(400);
  });

  it('maps latest to search_by_date', async () => {
    const spy = vi.fn(async (_url: unknown) => new Response(JSON.stringify({ hits: [{ objectID: '1' }] }), { status: 200 }));
    globalThis.fetch = spy as unknown as typeof fetch;
    const { GET } = await import('../../app/api/reader/stories/route.js');
    await GET(new Request('http://localhost/api/reader/stories?type=latest'));
    expect(String(spy.mock.calls[0]?.[0])).toContain('/search_by_date?tags=story');
  });
});
