// backend/test/hn-store.test.ts
import { beforeEach, describe, expect, it, vi } from 'vitest';

describe('hn-store (in-memory)', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.DATABASE_URL;
    delete process.env.NODE_ENV;
  });

  it('upsert 后按 id 读回，保持插入语义', async () => {
    const { upsertItems, readItems } = await import('../lib/hn-store.js');
    await upsertItems([
      { id: 1, raw: { id: 1, type: 'story', title: 'a' } },
      { id: 2, raw: { id: 2, type: 'comment', text: 'c' } },
    ]);
    const rows = await readItems([1, 2, 3]);
    expect(rows.get(1)?.raw).toMatchObject({ id: 1, title: 'a' });
    expect(rows.get(2)?.raw).toMatchObject({ id: 2, text: 'c' });
    expect(rows.has(3)).toBe(false); // 未落库 ≠ missing
  });

  it('HN null（已删除）存为 missing，读回为 null 语义', async () => {
    const { upsertItems, readItems } = await import('../lib/hn-store.js');
    await upsertItems([{ id: 9, raw: null }]);
    const rows = await readItems([9]);
    expect(rows.get(9)?.raw).toBeNull();
    expect(rows.get(9)?.missing).toBe(true);
  });

  it('重复 upsert 覆盖旧值并刷新 fetchedAt', async () => {
    const { upsertItems, readItems } = await import('../lib/hn-store.js');
    await upsertItems([{ id: 1, raw: { id: 1, score: 1 } }]);
    await upsertItems([{ id: 1, raw: { id: 1, score: 2 } }]);
    const rows = await readItems([1]);
    expect(rows.get(1)?.raw).toMatchObject({ score: 2 });
  });

  it('StoryList 存取 roundtrip', async () => {
    const { saveStoryList, readStoryList } = await import('../lib/hn-store.js');
    await saveStoryList('top', [5, 6, 7]);
    const got = await readStoryList('top');
    expect(got?.ids).toEqual([5, 6, 7]);
    expect(await readStoryList('latest')).toBeUndefined();
  });

  it('oldestFetchedStories 只返回超过最小树龄的 story，按 fetchedAt 升序', async () => {
    const { upsertItems, oldestFetchedStories } = await import('../lib/hn-store.js');
    await upsertItems([
      { id: 1, raw: { id: 1, type: 'story' } },
      { id: 2, raw: { id: 2, type: 'comment' } },
    ]);
    await oldestFetchedStories; // import 就绪
    // id=1 刚写入，minAgeMinutes=60 时不应入选
    expect(await oldestFetchedStories(5, 60)).toEqual([]);
  });

  it('__testBackdateItem 把 fetchedAt 回拨（仅测试用）', async () => {
    const { upsertItems, oldestFetchedStories, __testBackdateItem } = await import('../lib/hn-store.js');
    await upsertItems([{ id: 1, raw: { id: 1, type: 'story' } }]);
    await __testBackdateItem(1, 120);
    expect(await oldestFetchedStories(5, 60)).toEqual([1]);
  });
});
