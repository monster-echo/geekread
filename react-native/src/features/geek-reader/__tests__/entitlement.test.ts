import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('entitlement', () => {
  beforeEach(() => {
    vi.resetModules();
    process.env.EXPO_PUBLIC_API_URL = 'http://api.test';
    process.env.EXPO_PUBLIC_APP_ID = 'geekread';
    process.env.EXPO_PUBLIC_APP_ENVIRONMENT = 'development';
  });

  it('fetches and caches the entitlement token', async () => {
    const calls: number[] = [];
    globalThis.fetch = vi.fn(async () => {
      calls.push(1);
      return new Response(JSON.stringify({ token: 'jwt-1', expiresAt: Math.floor(Date.now() / 1000) + 3600 }), { status: 200 });
    }) as unknown as typeof fetch;
    const { setSessionTokenReader, setInstallIdReader, getEntitlementToken, clearEntitlementCache } = await import('../data/entitlement');
    setSessionTokenReader(async () => 'session');
    setInstallIdReader(async () => 'inst');
    clearEntitlementCache();
    const t1 = await getEntitlementToken();
    const t2 = await getEntitlementToken();
    expect(t1).toBe('jwt-1');
    expect(t2).toBe('jwt-1');
    expect(calls.length).toBe(1); // 缓存命中
  });

  it('returns null when not signed in', async () => {
    const fetchSpy = vi.fn();
    globalThis.fetch = fetchSpy as unknown as typeof fetch;
    const { setSessionTokenReader, getEntitlementToken, clearEntitlementCache } = await import('../data/entitlement');
    setSessionTokenReader(async () => null);
    clearEntitlementCache();
    expect(await getEntitlementToken()).toBeNull();
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
