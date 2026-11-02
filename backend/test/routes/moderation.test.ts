import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function resetEnv() {
  vi.resetModules();
  delete process.env.DATABASE_URL;
  delete process.env.WARM_CACHE_TOKEN;
  delete process.env.OPS_TOKEN;
  delete process.env.MODERATION_MODE;
  delete process.env.MODERATION_HTTP_URL;
  process.env.OPS_TOKEN = 'ops-secret';
}

describe('内容审核管理接口 /api/reader/moderation', () => {
  beforeEach(resetEnv);
  afterEach(() => vi.restoreAllMocks());

  async function call(path: string, init?: RequestInit) {
    const { GET, POST } = await import('../../app/api/reader/moderation/route.js');
    const request = new Request(`http://localhost/api/reader/moderation${path}`, init);
    return init?.method === 'POST' ? POST(request) : GET(request);
  }

  it('未带 token 拒绝访问', async () => {
    const res = await call('?view=reports');
    expect(res.status).toBe(403);
  });

  it('举报列表 + 处置（dismiss）标记 reviewedAt', async () => {
    const { saveReport } = await import('../../lib/report-store.js');
    await saveReport({ storyId: 10, commentId: 20, reason: 'illegal', text: '举报样本文本', installId: 'i1', ts: Date.now() });
    const list = await (await call('?view=reports&token=ops-secret')).json();
    expect(list.reports).toHaveLength(1);
    expect(list.reports[0]).toMatchObject({ storyId: 10, commentId: 20, reviewedAt: null });
    const reportId = list.reports[0].id as number;

    const resolved = await (await call('?token=ops-secret', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'resolve', reportId, decision: 'dismiss' }),
    })).json();
    expect(resolved).toMatchObject({ ok: true, reviewed: true });

    const after = await (await call('?view=reports&token=ops-secret')).json();
    expect(after.reports[0].reviewedAt).toBeTypeOf('number');
  });

  it('下架评论：写黑名单并清理该文本的翻译缓存', async () => {
    const { upsertItems } = await import('../../lib/hn-store.js');
    const { cacheTranslation, getCachedTranslation } = await import('../../lib/cache-store.js');
    await upsertItems([{ id: 22, raw: { id: 22, type: 'comment', text: '这是一条违规文本' } }]);
    await cacheTranslation('这是一条违规文本', 'zh-Hans', '违规译文');

    const body = await (await call('?token=ops-secret', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'block', kind: 'comment', targetId: 22, reason: 'illegal' }),
    })).json();
    expect(body.ok).toBe(true);
    expect(body.purgedTranslations).toBe(1);

    expect(await getCachedTranslation('这是一条违规文本', 'zh-Hans')).toBeUndefined();
    const blocks = await (await call('?view=blocks&token=ops-secret')).json();
    expect(blocks.blocks.map((block: { targetId: number }) => block.targetId)).toContain(22);

    // 解封
    const removed = await (await call('?token=ops-secret', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'unblock', kind: 'comment', targetId: 22 }),
    })).json();
    expect(removed).toMatchObject({ ok: true, removed: true });
  });

  it('下架 story：同时清理摘要与标题翻译缓存', async () => {
    const { upsertItems } = await import('../../lib/hn-store.js');
    const { cacheSummary, cacheTranslation, getCachedSummary, getCachedTranslation } = await import('../../lib/cache-store.js');
    await upsertItems([{ id: 33, raw: { id: 33, type: 'story', title: '违规标题', text: '违规正文' } }]);
    await cacheTranslation('违规标题', 'zh-Hans', '违规标题译文');
    await cacheSummary(33, 'zh-Hans', '违规摘要');

    const body = await (await call('?token=ops-secret', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'block', kind: 'story', targetId: 33, reason: 'illegal' }),
    })).json();
    expect(body.purgedTranslations).toBe(1);
    expect(body.purgedSummaries).toBe(1);
    expect(await getCachedSummary(33, 'zh-Hans')).toBeUndefined();
    expect(await getCachedTranslation('违规标题', 'zh-Hans')).toBeUndefined();
  });
});