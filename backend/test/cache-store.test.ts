import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('cache-store (in-memory)', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.DATABASE_URL;
    vi.stubEnv('NODE_ENV', 'test');
  });

  it('caches and reads a translation', async () => {
    const { cacheTranslation, getCachedTranslation } = await import('../lib/cache-store.js');
    await cacheTranslation('hello', 'zh-Hans', '你好');
    expect(await getCachedTranslation('hello', 'zh-Hans')).toBe('你好');
    expect(await getCachedTranslation('bye', 'zh-Hans')).toBeUndefined();
  });

  it('translation key 隔离语言与模型（换 MODEL_NAME 后不命中）', async () => {
    process.env.MODEL_NAME = 'model-a';
    const { cacheTranslation, getCachedTranslation } = await import('../lib/cache-store.js');
    await cacheTranslation('hello', 'zh-Hans', '你好');
    process.env.MODEL_NAME = 'model-b';
    expect(await getCachedTranslation('hello', 'zh-Hans')).toBeUndefined();
  });

  it('empty translation is not cached', async () => {
    const { cacheTranslation, getCachedTranslation } = await import('../lib/cache-store.js');
    await cacheTranslation('hello', 'zh-Hans', '   ');
    expect(await getCachedTranslation('hello', 'zh-Hans')).toBeUndefined();
  });

  it('caches and reads a summary（永久，同 storyId+lang 只存一份）', async () => {
    const { cacheSummary, getCachedSummary } = await import('../lib/cache-store.js');
    await cacheSummary(42, 'zh-Hans', '要点');
    expect(await getCachedSummary(42, 'zh-Hans')).toBe('要点');
    await cacheSummary(42, 'zh-Hans', '更新后的要点');
    expect(await getCachedSummary(42, 'zh-Hans')).toBe('更新后的要点');
    expect(await getCachedSummary(43, 'zh-Hans')).toBeUndefined();
  });
});
