// backend/lib/scheduler.ts
import { tick } from './sync';
import { hnHealth } from './hn-health';

/**
 * 自调度循环：间隔 = hnHealth.intervalMs()（AIMD 自适应）。
 * 用 setTimeout 链而非 setInterval，间隔才能动态变化。
 */
export function startScheduler(): void {
  const run = async (): Promise<void> => {
    try {
      const result = await tick();
      process.stdout.write(`[geekread][sync] tick: ${JSON.stringify(result)}\n`);
    } catch (error) {
      process.stderr.write(`[geekread][sync] tick crashed: ${String(error)}\n`);
    }
    setTimeout(run, hnHealth.intervalMs()).unref();
  };
  // 启动延迟 10s 错峰（避开服务刚起时的流量高峰）
  setTimeout(run, 10_000).unref();
}
