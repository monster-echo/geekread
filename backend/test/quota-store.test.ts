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

  it('topic reservation: first claim per topic charges, same-topic later claims free', async () => {
    const { reserveTopicTranslation } = await import('../lib/quota-store.js');
    const day = '2026-09-01';
    const r1 = await reserveTopicTranslation(day, 'c1', 11, 2, 10);
    expect(r1).toMatchObject({ allowed: true, charged: true, remainingTopics: 1 });
    const r2 = await reserveTopicTranslation(day, 'c1', 11, 2, 10);
    expect(r2).toMatchObject({ allowed: true, charged: false, remainingTopics: 1 });
    const r3 = await reserveTopicTranslation(day, 'c1', 22, 2, 10);
    expect(r3).toMatchObject({ allowed: true, charged: true, remainingTopics: 0 });
    const r4 = await reserveTopicTranslation(day, 'c1', 33, 2, 10);
    expect(r4).toMatchObject({ allowed: false, charged: false });
  });

  it('topic reservation: request cap bounds batches within one topic', async () => {
    const { reserveTopicTranslation } = await import('../lib/quota-store.js');
    const day = '2026-09-01';
    for (let i = 0; i < 3; i++) {
      const r = await reserveTopicTranslation(day, 'cc', 5, 100, 3);
      expect(r.allowed).toBe(true);
    }
    const over = await reserveTopicTranslation(day, 'cc', 5, 100, 3);
    expect(over.allowed).toBe(false);
  });
});
