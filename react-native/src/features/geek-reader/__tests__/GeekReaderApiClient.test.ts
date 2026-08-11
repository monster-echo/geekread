import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('GeekReaderApiClient', () => {
  beforeEach(() => {
    process.env.EXPO_PUBLIC_GEEKREAD_BACKEND_URL = 'http://backend.test';
    vi.resetModules();
  });

  it('fetches stories with type query', async () => {
    const spy = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      expect(String(url)).toContain('/api/reader/stories?type=top');
      expect(init?.method ?? 'GET').toBe('GET');
      return new Response(JSON.stringify({ ids: [1, 2], cached: false, stale: false }), { status: 200 });
    });
    globalThis.fetch = spy as unknown as typeof fetch;
    const { setInstallIdReader, setBearerReader, fetchStories } = await import('../data/GeekReaderApiClient');
    setInstallIdReader(async () => 'inst-1');
    setBearerReader(async () => null);
    const r = await fetchStories('top');
    expect(r.ids).toEqual([1, 2]);
  });

  it('sends x-install-id and Authorization headers on translate', async () => {
    const seen: Record<string, string> = {};
    globalThis.fetch = vi.fn(async (_u: unknown, init?: RequestInit) => {
      new Headers(init?.headers).forEach((v, k) => { seen[k] = v; });
      return new Response(JSON.stringify({ results: [{ key: 'k', translation: '你好' }] }), { status: 200 });
    }) as unknown as typeof fetch;
    const { setInstallIdReader, setBearerReader, translateBatch } = await import('../data/GeekReaderApiClient');
    setInstallIdReader(async () => 'inst-1');
    setBearerReader(async () => 'pro-token');
    await translateBatch({ targetLanguage: 'zh-Hans', entries: [{ key: 'k', text: 'hello' }] });
    expect(seen['x-install-id']).toBe('inst-1');
    expect(seen['authorization']).toBe('Bearer pro-token');
  });

  it('omits Authorization when no token', async () => {
    const seen: Record<string, string> = {};
    globalThis.fetch = vi.fn(async (_u: unknown, init?: RequestInit) => {
      new Headers(init?.headers).forEach((v, k) => { seen[k] = v; });
      return new Response(JSON.stringify({ results: [] }), { status: 200 });
    }) as unknown as typeof fetch;
    const { setInstallIdReader, setBearerReader, translateBatch } = await import('../data/GeekReaderApiClient');
    setInstallIdReader(async () => 'inst-1');
    setBearerReader(async () => null);
    await translateBatch({ targetLanguage: 'zh-Hans', entries: [{ key: 'k', text: 'hi' }] });
    expect(seen['x-install-id']).toBe('inst-1');
    expect(seen['authorization']).toBeUndefined();
  });

  it('throws on non-ok', async () => {
    globalThis.fetch = vi.fn(async () => new Response('err', { status: 500 })) as unknown as typeof fetch;
    const { setInstallIdReader, setBearerReader, fetchStories } = await import('../data/GeekReaderApiClient');
    setInstallIdReader(async () => 'inst-1');
    setBearerReader(async () => null);
    await expect(fetchStories('top')).rejects.toThrow();
  });
});
