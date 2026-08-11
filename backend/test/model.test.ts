import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function okResponse(content: string | unknown) {
  const body = typeof content === 'string'
    ? { choices: [{ message: { content } }] }
    : content;
  return new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });
}

describe('model', () => {
  beforeEach(() => {
    process.env.MODEL_API_URL = 'https://llm.example.com/chat';
    process.env.MODEL_API_KEY = 'k';
    process.env.MODEL_NAME = 'test-model';
  });
  afterEach(() => vi.restoreAllMocks());

  it('translates via OpenAI-compatible chat', async () => {
    const spy = vi.fn(async (_url: unknown, init?: RequestInit) => okResponse('你好'));
    globalThis.fetch = spy as unknown as typeof fetch;
    const { translateWithModel } = await import('../lib/model.js');
    expect(await translateWithModel('hello', 'zh-Hans')).toBe('你好');
    const init = spy.mock.calls[0]?.[1] as RequestInit | undefined;
    const body = JSON.parse((init?.body as string) ?? '{}');
    expect(body.messages[0].role).toBe('system');
    expect(body.messages[0].content).toContain('Simplified Chinese');
  });

  it('rejects unsupported language', async () => {
    const { translateWithModel } = await import('../lib/model.js');
    await expect(translateWithModel('hi', 'fr')).rejects.toThrow('unsupported_target_language');
  });

  it('rejects empty translation', async () => {
    globalThis.fetch = vi.fn(async () => okResponse('   ')) as unknown as typeof fetch;
    const { translateWithModel } = await import('../lib/model.js');
    await expect(translateWithModel('hi', 'zh-Hans')).rejects.toThrow('empty_translation');
  });

  it('surfaces upstream error status', async () => {
    globalThis.fetch = vi.fn(async () => new Response('err', { status: 500 })) as unknown as typeof fetch;
    const { translateWithModel } = await import('../lib/model.js');
    await expect(translateWithModel('hi', 'zh-Hans')).rejects.toThrow('model_upstream_500');
  });
});
