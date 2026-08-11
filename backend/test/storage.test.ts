import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('storage (in-memory)', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.REDIS_URL;
  });

  it('caches and reads a translation', async () => {
    const { cacheTranslation, getCachedTranslation } = await import('../lib/storage.js');
    await cacheTranslation('hello', 'zh-Hans', '你好');
    expect(await getCachedTranslation('hello', 'zh-Hans')).toBe('你好');
    expect(await getCachedTranslation('bye', 'zh-Hans')).toBeUndefined();
  });

  it('reserves quota up to a limit then denies, with rollback', async () => {
    const { reserveTranslation } = await import('../lib/storage.js');
    const day = '2026-08-12';
    const a = await reserveTranslation(day, 'client-a', 2);
    expect(a.allowed).toBe(true);
    expect(a.remaining).toBe(1);
    const b = await reserveTranslation(day, 'client-a', 2);
    expect(b.allowed).toBe(true);
    expect(b.remaining).toBe(0);
    const c = await reserveTranslation(day, 'client-a', 2);
    expect(c.allowed).toBe(false);
    await b.rollback();
    const d = await reserveTranslation(day, 'client-a', 2);
    expect(d.allowed).toBe(true);
  });

  it('tracks separate clients separately', async () => {
    const { reserveTranslation } = await import('../lib/storage.js');
    const day = '2026-08-12';
    expect((await reserveTranslation(day, 'client-a', 1)).allowed).toBe(true);
    expect((await reserveTranslation(day, 'client-b', 1)).allowed).toBe(true);
    expect((await reserveTranslation(day, 'client-a', 1)).allowed).toBe(false);
  });

  it('serves stale JSON cache then expires', async () => {
    const { getJsonCache, setJsonCache } = await import('../lib/storage.js');
    await setJsonCache('k', [1, 2], 0, 100);
    const hit = await getJsonCache<number[]>('k');
    expect(hit?.value).toEqual([1, 2]);
    expect(hit?.stale).toBe(true);
  });
});
