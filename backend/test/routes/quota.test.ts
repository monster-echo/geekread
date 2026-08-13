import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('GET /api/reader/quota', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.REDIS_URL;
    process.env.ENTITLEMENT_SIGNING_SECRET = 's';
    process.env.FREE_DAILY_TRANSLATIONS = '20';
    process.env.PRO_DAILY_TRANSLATIONS = '500';
  });
  afterEach(() => vi.restoreAllMocks());

  it('returns free quota without entitlement', async () => {
    const { GET } = await import('../../app/api/reader/quota/route.js');
    const res = await GET(new Request('http://localhost/api/reader/quota', {
      headers: { 'x-install-id': 'c1' },
    }));
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ used: 0, limit: 20, remaining: 20, isPro: false });
  });

  it('reflects today usage after reserving one', async () => {
    const { reserveDaily, today } = await import('../../lib/quota.js');
    await reserveDaily(today(), 'c1', false);
    const { GET } = await import('../../app/api/reader/quota/route.js');
    const res = await GET(new Request('http://localhost/api/reader/quota', {
      headers: { 'x-install-id': 'c1' },
    }));
    const body = await res.json();
    expect(body).toMatchObject({ used: 1, limit: 20, remaining: 19, isPro: false });
  });

  it('returns pro quota with valid entitlement', async () => {
    const { signEntitlement } = await import('../../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) + 3600 });
    const { GET } = await import('../../app/api/reader/quota/route.js');
    const res = await GET(new Request('http://localhost/api/reader/quota', {
      headers: { 'x-install-id': 'c2', authorization: `Bearer ${token}` },
    }));
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ limit: 500, isPro: true });
  });

  it('400 when install id missing', async () => {
    const { GET } = await import('../../app/api/reader/quota/route.js');
    const res = await GET(new Request('http://localhost/api/reader/quota'));
    expect(res.status).toBe(400);
  });
});
