// backend/instrumentation.ts
/**
 * Next.js 启动钩子：生产环境拉起 HN 预热调度器（60s 级，AIMD 自适应）。
 * dev 不自动起（手动打 /api/reader/warm 验证）。
 */
export async function register(): Promise<void> {
  if (process.env.NEXT_RUNTIME !== 'nodejs') return;
  if (process.env.NODE_ENV !== 'production') return;
  const { startScheduler } = await import('./lib/scheduler');
  startScheduler();
}
