import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ENV_KEYS = [
  'MODERATION_MODE',
  'MODERATION_KEYWORDS_PATH',
  'MODERATION_HTTP_URL',
  'MODERATION_HTTP_TOKEN',
  'MODERATION_HTTP_TIMEOUT_MS',
  'MODERATION_FAIL_MODE',
  'OUTBOUND_FILTER',
];

describe('内容审核模块', () => {
  beforeEach(async () => {
    vi.resetModules();
    for (const key of ENV_KEYS) delete process.env[key];
    const { resetModerationCache } = await import('../lib/moderation.js');
    resetModerationCache();
  });
  afterEach(() => {
    vi.restoreAllMocks();
    for (const key of ENV_KEYS) delete process.env[key];
  });

  it('命中基线词库（中文夹杂空格/零宽字符也能识别）', async () => {
    const { scanKeywords } = await import('../lib/moderation.js');
    expect(scanKeywords('这里的代 开 发 票 广告').blocked).toBe(true);
    expect(scanKeywords('代\u200b开\u200b发\u200b票').blocked).toBe(true);
    expect(scanKeywords('ＧＥＥＫ 正在阅读 Hacker News').blocked).toBe(false);
  });

  it('自定义词库：英文按单词边界匹配，避免误伤', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'geekread-mod-'));
    const path = join(dir, 'keywords.json');
    writeFileSync(path, JSON.stringify({ version: 1, categories: { test: ['bomb'] } }), 'utf8');
    process.env.MODERATION_KEYWORDS_PATH = path;
    const { scanKeywords, resetModerationCache } = await import('../lib/moderation.js');
    resetModerationCache();
    expect(scanKeywords('how to make a bomb').blocked).toBe(true);
    expect(scanKeywords('bombastic style').blocked).toBe(false);
  });

  it('MODERATION_MODE=off 时全部放行', async () => {
    process.env.MODERATION_MODE = 'off';
    const { reviewTexts, scanKeywords } = await import('../lib/moderation.js');
    expect(scanKeywords('代开发票').blocked).toBe(true); // 同步扫描本身仍可单独使用
    const results = await reviewTexts(['代开发票', '正常技术讨论']);
    expect(results.every((result) => !result.blocked)).toBe(true);
  });

  it('http 审核服务命中 → blocked，批量一次请求', async () => {
    process.env.MODERATION_MODE = 'http';
    process.env.MODERATION_HTTP_URL = 'https://moderation.test/review';
    process.env.MODERATION_HTTP_TOKEN = 't';
    const spy = vi.fn(async () => new Response(JSON.stringify({
      results: [{ flagged: false, labels: [] }, { flagged: true, labels: ['porn'], reason: 'adult' }],
    }), { status: 200 }));
    globalThis.fetch = spy as unknown as typeof fetch;
    const { reviewTexts, resetModerationCache } = await import('../lib/moderation.js');
    resetModerationCache();
    const results = await reviewTexts(['hello', 'bad content']);
    expect(results[0]?.blocked).toBe(false);
    expect(results[1]?.blocked).toBe(true);
    expect(results[1]?.labels).toContain('porn');
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it('http 服务故障：默认 fail-open 放行，MODERATION_FAIL_MODE=closed 时拦截', async () => {
    process.env.MODERATION_MODE = 'http';
    process.env.MODERATION_HTTP_URL = 'https://moderation.test/review';
    globalThis.fetch = vi.fn(async () => new Response('boom', { status: 500 })) as unknown as typeof fetch;

    const openModule = await import('../lib/moderation.js');
    openModule.resetModerationCache();
    const openResults = await openModule.reviewTexts(['hello']);
    expect(openResults[0]?.blocked).toBe(false);

    vi.resetModules();
    process.env.MODERATION_MODE = 'http';
    process.env.MODERATION_HTTP_URL = 'https://moderation.test/review';
    process.env.MODERATION_FAIL_MODE = 'closed';
    const closedModule = await import('../lib/moderation.js');
    closedModule.resetModerationCache();
    const closedResults = await closedModule.reviewTexts(['hello']);
    expect(closedResults[0]?.blocked).toBe(true);
    expect(closedResults[0]?.reason).toBe('moderation_unavailable');
  });
});