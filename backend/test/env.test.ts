import { afterEach, describe, expect, it } from 'vitest';

describe('env', () => {
  afterEach(() => {
    delete process.env.FREE_DAILY_TRANSLATIONS;
    delete process.env.PRO_DAILY_TRANSLATIONS;
  });

  it('returns configured limits', async () => {
    process.env.FREE_DAILY_TRANSLATIONS = '7';
    process.env.PRO_DAILY_TRANSLATIONS = '999';
    const { reloadEnv, env } = await import('../lib/env.js');
    reloadEnv();
    expect(env().freeDailyTranslations).toBe(7);
    expect(env().proDailyTranslations).toBe(999);
  });

  it('falls back to defaults 20/500', async () => {
    const { reloadEnv, env } = await import('../lib/env.js');
    reloadEnv();
    expect(env().freeDailyTranslations).toBe(20);
    expect(env().proDailyTranslations).toBe(500);
  });
});
