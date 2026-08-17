// backend/test/hn-health.test.ts
import { beforeEach, describe, expect, it } from 'vitest';

describe('hn-health (AIMD)', () => {
  beforeEach(async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    hnHealth.reset();
  });

  it('level 0：60s 间隔、树预算 5', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    expect(hnHealth.intervalMs()).toBe(60_000);
    expect(hnHealth.treeBudget()).toBe(5);
  });

  it('429 立即降一级；恢复需连续 10 个干净 tick', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    hnHealth.noteRequest(false, { status: 429 });
    expect(hnHealth.intervalMs()).toBe(120_000);
    expect(hnHealth.treeBudget()).toBe(2);

    for (let i = 0; i < 9; i++) hnHealth.noteTickClean();
    expect(hnHealth.intervalMs()).toBe(120_000); // 9 次还不够
    hnHealth.noteTickClean();
    expect(hnHealth.intervalMs()).toBe(60_000);  // 第 10 次恢复
  });

  it('错误率 >30%（窗口 100）触发降级', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    for (let i = 0; i < 69; i++) hnHealth.noteRequest(true);
    for (let i = 0; i < 31; i++) hnHealth.noteRequest(false);
    expect(hnHealth.currentLevel()).toBe(1); // 31% > 30%
  });

  it('连续降级封顶 600s；Retry-After 直接遵守', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    hnHealth.noteRequest(false, { status: 429, retryAfterSeconds: 45 });
    expect(hnHealth.intervalMs()).toBeGreaterThanOrEqual(44_000);
    expect(hnHealth.intervalMs()).toBeLessThanOrEqual(45_000);
    // 等 Retry-After 过期后再验证封顶
    const { hnHealth: h } = await import('../lib/hn-health.js');
    (h as unknown as { retryUntil: number }).retryUntil = 0; // 测试直通：清除 Retry-After
    for (let i = 0; i < 12; i++) hnHealth.noteTickClean(); // 恢复到 level 0
    hnHealth.noteRequest(false, { status: 429 });
    hnHealth.noteRequest(false, { status: 429 });
    hnHealth.noteRequest(false, { status: 429 });
    expect(hnHealth.intervalMs()).toBe(600_000);
    expect(hnHealth.treeBudget()).toBe(0);
  });

  it('正常请求不改变 level', async () => {
    const { hnHealth } = await import('../lib/hn-health.js');
    for (let i = 0; i < 100; i++) hnHealth.noteRequest(true);
    expect(hnHealth.currentLevel()).toBe(0);
  });
});
