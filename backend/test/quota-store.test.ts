// backend/test/quota-store.test.ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('quota-store (in-memory)', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.DATABASE_URL;
    vi.stubEnv('NODE_ENV', 'test');
  });

  it('reserves quota up to a limit then denies, with rollback', async () => {
    const { reserveTranslation } = await import('../lib/quota-store.js');
    const day = '2026-08-18';
    const a = await reserveTranslation(day, 'client-a', 2);
    expect(a.allowed).toBe(true);
    expect(a.remaining).toBe(1);
    const b = await reserveTranslation(day, 'client-a', 2);
    expect(b.allowed).toBe(true);
    expect(b.remaining).toBe(0);
    const c = await reserveTranslation(day, 'client-a', 2);
    expect(c.allowed).toBe(false);
    // 回滚 b 后可再预留一次
    await b.rollback();
    const d = await reserveTranslation(day, 'client-a', 2);
    expect(d.allowed).toBe(true);
  });

  it('clients are isolated', async () => {
    const { reserveTranslation } = await import('../lib/quota-store.js');
    const day = '2026-08-18';
    await reserveTranslation(day, 'client-a', 1);
    const other = await reserveTranslation(day, 'client-b', 1);
    expect(other.allowed).toBe(true);
  });

  it('peekTranslation reads current usage', async () => {
    const { reserveTranslation, peekTranslation } = await import('../lib/quota-store.js');
    const day = '2026-08-18';
    await reserveTranslation(day, 'client-c', 5);
    await reserveTranslation(day, 'client-c', 5);
    expect(await peekTranslation(day, 'client-c')).toBe(2);
  });
});
