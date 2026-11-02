import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function llm(map: Record<string, string>) {
  return vi.fn(async (_url: unknown, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body ?? '{}')) as { messages: { content: string }[] };
    const src = body.messages[1]?.content ?? '';
    const out = map[src] ?? 'TRANSLATED';
    return new Response(JSON.stringify({ choices: [{ message: { content: out } }] }), { status: 200 });
  }) as unknown as typeof fetch;
}

describe('POST /api/translate — 内容合规拦截', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.DATABASE_URL;
    delete process.env.MODERATION_MODE;
    delete process.env.MODERATION_HTTP_URL;
    process.env.MODEL_API_URL = 'https://llm/chat';
    process.env.MODEL_API_KEY = 'k';
    process.env.MODEL_NAME = 'm';
    process.env.ENTITLEMENT_SIGNING_SECRET = 's';
    process.env.FREE_DAILY_TRANSLATIONS = '20';
    process.env.PRO_DAILY_TRANSLATIONS = '500';
  });
  afterEach(() => vi.restoreAllMocks());

  it('命中关键词的条目不调模型、不扣配额，整批其余条目正常翻译', async () => {
    const fetchSpy = llm({ hello: '你好' });
    globalThis.fetch = fetchSpy;
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c-blocked' },
      body: JSON.stringify({
        targetLanguage: 'zh-Hans',
        entries: [
          { key: 'bad', text: '专业代 开 发 票，可验证' },
          { key: 'ok', text: 'hello' },
        ],
      }),
    }));
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body.results[0]).toMatchObject({ key: 'bad', error: 'blocked', blocked: true });
    expect(body.results[1]).toMatchObject({ key: 'ok', translation: '你好' });
    expect(body.blocked).toBe(1);
    // 只有正常条目消耗配额
    expect(body.remainingTranslations).toBe(19);
    // 模型只被调用一次（被拦条目未发出）
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it('free 免费通道同样拦截', async () => {
    const fetchSpy = llm({});
    globalThis.fetch = fetchSpy;
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c-free' },
      body: JSON.stringify({
        free: true,
        targetLanguage: 'zh-Hans',
        entries: [{ key: 'bad', text: '网络赌博平台推荐' }],
      }),
    }));
    const body = await res.json();
    expect(body.results[0]).toMatchObject({ error: 'blocked', blocked: true });
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('story 被拉黑时整批拦截（即使文本未命中词库）', async () => {
    const { addBlock } = await import('../../lib/blocklist.js');
    await addBlock({ kind: 'story', targetId: 424242, reason: 'manual' });
    const fetchSpy = llm({});
    globalThis.fetch = fetchSpy;
    const { POST } = await import('../../app/api/translate/route.js');
    const res = await POST(new Request('http://localhost/api/translate', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c-story' },
      body: JSON.stringify({
        targetLanguage: 'zh-Hans',
        storyId: 424242,
        entries: [{ key: 'a', text: '正常技术讨论文本' }],
      }),
    }));
    const body = await res.json();
    expect(body.results[0]).toMatchObject({ error: 'blocked', blocked: true });
    expect(body.remainingTopics).toBeUndefined();
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});