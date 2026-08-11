import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('translationCache', () => {
  beforeEach(async () => {
    vi.useFakeTimers();
    const { setTranslationTransport, clearTranslationCache } = await import('../application/translationCache');
    setTranslationTransport(async (req) => ({
      results: req.entries.map((e) => ({ key: e.key, translation: `[${e.text}]` })),
    }));
    clearTranslationCache();
  });

  it('dedupes identical in-flight texts', async () => {
    const { translate } = await import('../application/translationCache');
    const t1 = translate('hello', 'zh-Hans');
    const t2 = translate('hello', 'zh-Hans');
    await vi.advanceTimersByTimeAsync(60);
    const [a, b] = await Promise.all([t1, t2]);
    expect(a).toBe('[hello]');
    expect(b).toBe('[hello]');
  });

  it('caches results for repeat calls', async () => {
    const calls: number[] = [];
    const { setTranslationTransport, clearTranslationCache, translate } = await import('../application/translationCache');
    setTranslationTransport(async (req) => {
      calls.push(req.entries.length);
      return { results: req.entries.map((e) => ({ key: e.key, translation: `T${e.text}` })) };
    });
    clearTranslationCache();
    const p = translate('x', 'zh-Hans');
    await vi.advanceTimersByTimeAsync(60);
    await p;
    await vi.advanceTimersByTimeAsync(60);
    const r = await translate('x', 'zh-Hans');
    expect(r).toBe('Tx');
    expect(calls).toEqual([1]);
  });

  it('batches multiple texts in one request', async () => {
    const seen: number[] = [];
    const { setTranslationTransport, clearTranslationCache, translate } = await import('../application/translationCache');
    setTranslationTransport(async (req) => {
      seen.push(req.entries.length);
      return { results: req.entries.map((e) => ({ key: e.key, translation: 't' })) };
    });
    clearTranslationCache();
    const ps = [translate('a', 'zh-Hans'), translate('b', 'zh-Hans'), translate('c', 'zh-Hans')];
    await vi.advanceTimersByTimeAsync(60);
    await Promise.all(ps);
    expect(seen).toEqual([3]);
  });
});
