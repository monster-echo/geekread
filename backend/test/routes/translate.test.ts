import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function llm(map: Record<string, string>) {
  return vi.fn(async (_url: unknown, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body ?? '{}')) as { messages: { content: string }[] };
    const src = body.messages[1]?.content ?? '';
    const out = map[src] ?? 'TRANSLATED';
    return new Response(JSON.stringify({ choices: [{ message: { content: out } }] }), { status: 200 });
  }) as unknown as typeof fetch;
}

describe('POST /api/translate', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.REDIS_URL;
    process.env.MODEL_API_URL = 'https://llm/chat';
    process.env.MODEL_API_KEY = 'k';
    process.env.MODEL_NAME = 'm';
    process.env.ENTITLEMENT_SIGNING_SECRET = 's';
    process.env.FREE_DAILY_TRANSLATIONS = '20';
    process.env.PRO_DAILY_TRANSLATIONS = '500';
  });
  afterEach(() => vi.restoreAllMocks());

  it('translates a batch and returns keyed results', async () => {
    globalThis.fetch = llm({ hello: '你好' });
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c1' },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries: [{ key: 'k1', text: 'hello' }] }),
    }));
    const body = await res.json();
    expect(body.results[0]).toMatchObject({ key: 'k1', translation: '你好' });
    expect(body.remainingTranslations).toBe(19);
  });

  it('serves cached translation without consuming quota', async () => {
    const { cacheTranslation } = await import('../../lib/cache-store.js');
    await cacheTranslation('hello', 'zh-Hans', '你好');
    const fetchSpy = vi.fn();
    globalThis.fetch = fetchSpy as unknown as typeof fetch;
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c1' },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries: [{ key: 'k1', text: 'hello' }] }),
    }));
    const body = await res.json();
    expect(body.results[0]).toMatchObject({ key: 'k1', translation: '你好', cached: true });
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('returns quota_exceeded when free limit hit', async () => {
    process.env.FREE_DAILY_TRANSLATIONS = '1';
    globalThis.fetch = llm({});
    const { POST } = await import('../../app/api/translate/route.js');
    const req = (entries: { key: string; text: string }[]) => new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c2' },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries }),
    });
    await POST(req([{ key: 'a', text: 'first' }]));
    const res2 = await POST(req([{ key: 'b', text: 'second' }]));
    const body2 = await res2.json();
    expect(body2.results[0].error).toBe('quota_exceeded');
  });

  it('Pro entitlement raises the limit', async () => {
    process.env.FREE_DAILY_TRANSLATIONS = '0';
    process.env.PRO_DAILY_TRANSLATIONS = '500';
    const { signEntitlement } = await import('../../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) + 3600 });
    globalThis.fetch = llm({});
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-install-id': 'c3',
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries: [{ key: 'a', text: 'hi' }] }),
    }));
    const body = await res.json();
    expect(body.results[0].translation).toBe('TRANSLATED');
  });

  it('400 when install id missing', async () => {
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ targetLanguage: 'zh-Hans', entries: [{ key: 'a', text: 'hi' }] }),
    }));
    expect(res.status).toBe(400);
  });
});
