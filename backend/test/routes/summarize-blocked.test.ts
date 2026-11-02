import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function llm(summary: string) {
  return vi.fn(async () => new Response(JSON.stringify({
    choices: [{ message: { content: summary } }],
  }), { status: 200 })) as unknown as typeof fetch;
}

function request(body: Record<string, unknown>): Request {
  return new Request('http://localhost/api/reader/summarize', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-install-id': 'sum-1' },
    body: JSON.stringify(body),
  });
}

describe('POST /api/reader/summarize — 内容合规拦截', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.DATABASE_URL;
    delete process.env.MODERATION_MODE;
    delete process.env.MODERATION_HTTP_URL;
    process.env.MODEL_API_URL = 'https://llm/chat';
    process.env.MODEL_API_KEY = 'k';
    process.env.MODEL_NAME = 'm';
    process.env.ENTITLEMENT_SIGNING_SECRET = 's';
  });
  afterEach(() => vi.restoreAllMocks());

  it('标题命中词库 → 403，不调用模型', async () => {
    const fetchSpy = llm('摘要');
    globalThis.fetch = fetchSpy;
    const { POST } = await import('../../app/api/reader/summarize/route.js');
    const res = await POST(request({ storyId: 1, targetLanguage: 'zh-Hans', title: '专业代开发票 快速办理', comments: [] }));
    expect(res.status).toBe(403);
    const body = await res.json();
    expect(body).toMatchObject({ error: 'content_blocked', blocked: true });
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('评论命中词库同样拦截', async () => {
    const fetchSpy = llm('摘要');
    globalThis.fetch = fetchSpy;
    const { POST } = await import('../../app/api/reader/summarize/route.js');
    const res = await POST(request({
      storyId: 2,
      targetLanguage: 'zh-Hans',
      title: '正常技术文章',
      comments: ['正常评论', '网络赌博 推广链接'],
    }));
    expect(res.status).toBe(403);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('story 被拉黑 → 403', async () => {
    const { addBlock } = await import('../../lib/blocklist.js');
    await addBlock({ kind: 'story', targetId: 3, reason: 'manual' });
    const fetchSpy = llm('摘要');
    globalThis.fetch = fetchSpy;
    const { POST } = await import('../../app/api/reader/summarize/route.js');
    const res = await POST(request({ storyId: 3, targetLanguage: 'zh-Hans', title: '正常技术文章', comments: [] }));
    expect(res.status).toBe(403);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('正常内容返回摘要', async () => {
    globalThis.fetch = llm('一句话摘要');
    const { POST } = await import('../../app/api/reader/summarize/route.js');
    const res = await POST(request({ storyId: 4, targetLanguage: 'zh-Hans', title: 'A new database', comments: ['nice'] }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.summary).toBe('一句话摘要');
  });
});