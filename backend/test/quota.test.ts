import { beforeEach, describe, expect, it } from 'vitest';

describe('quota', () => {
  beforeEach(async () => {
    delete process.env.REDIS_URL;
    delete process.env.FREE_DAILY_TRANSLATIONS;
    delete process.env.PRO_DAILY_TRANSLATIONS;
    process.env.ENTITLEMENT_SIGNING_SECRET = 's';
    const { reloadEnv } = await import('../lib/env.js');
    reloadEnv();
  });

  it('free limit defaults to 20', async () => {
    const { limitFor } = await import('../lib/quota.js');
    expect(limitFor(false)).toBe(20);
  });

  it('pro limit defaults to 500', async () => {
    const { limitFor } = await import('../lib/quota.js');
    expect(limitFor(true)).toBe(500);
  });

  it('reserves against the right limit', async () => {
    process.env.FREE_DAILY_TRANSLATIONS = '1';
    const { reloadEnv } = await import('../lib/env.js');
    reloadEnv();
    const { reserveDaily } = await import('../lib/quota.js');
    const day = '2026-08-12';
    const r1 = await reserveDaily(day, 'c1', false);
    expect(r1.allowed).toBe(true);
    const r2 = await reserveDaily(day, 'c1', false);
    expect(r2.allowed).toBe(false);
  });
});
