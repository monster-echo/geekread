// backend/lib/hn-health.ts

/**
 * HN 上游健康状态机（AIMD）：
 * - 降级（乘性）：429/Retry-After 立即；窗口错误率 >30% 降
 * - 恢复（加性）：连续 10 个无错误 tick 才降一级
 * - 级别 0~3 → 间隔 [60,120,300,600]s，树预算 [env WARM_TREE_BUDGET(默认5),2,0,0]
 * 进程内存态，不持久化；重启从 level 0 重新探测。
 */
const INTERVALS_MS = [60_000, 120_000, 300_000, 600_000] as const;
/** level 0 树预算由 env WARM_TREE_BUDGET 控制（默认 5），降级梯 2→0 固定 */
const BASE_TREE_BUDGET = Number(process.env.WARM_TREE_BUDGET ?? 5);
const TREE_BUDGETS = [BASE_TREE_BUDGET, 2, 0, 0];
const WINDOW = 100;
const ERROR_RATE_LIMIT = 0.3;
const CLEAN_TICKS_TO_RECOVER = 10;

export type RequestOutcome = { status?: number; retryAfterSeconds?: number };

class HnHealth {
  // retryUntil 用实例属性（测试直通用）
  retryUntil = 0;
  private level = 0;
  private window: boolean[] = [];
  private cleanTicks = 0;
  /** 错误率降级在恢复前只触发一次（防连续降到底） */
  private rateDegraded = false;

  reset(): void {
    this.level = 0;
    this.window = [];
    this.cleanTicks = 0;
    this.rateDegraded = false;
    this.retryUntil = 0;
  }

  /** 每个 HN 请求后调用（读路径 + 调度器都记）。 */
  noteRequest(ok: boolean, outcome: RequestOutcome = {}): void {
    this.window.push(ok);
    if (this.window.length > WINDOW) this.window.shift();
    const limited = outcome.status === 429 || outcome.retryAfterSeconds !== undefined;
    if (limited) {
      this.degrade();
      if (outcome.retryAfterSeconds !== undefined) {
        this.retryUntil = Math.max(this.retryUntil, Date.now() + outcome.retryAfterSeconds * 1000);
      }
      return;
    }
    // 窗口错误率超阈值 → 降一级
    this.checkErrorRate();
  }

  /** 每个 tick 结束且本 tick 无错误时调用。 */
  noteTickClean(): void {
    this.cleanTicks += 1;
    if (this.cleanTicks >= CLEAN_TICKS_TO_RECOVER && this.level > 0) {
      this.level -= 1;
      this.cleanTicks = 0;
    }
  }

  /** tick 开始时调用：窗口错误率超阈值 → 降一级。 */
  noteTickStart(): void {
    this.checkErrorRate();
  }

  private checkErrorRate(): void {
    if (this.window.length === 0) return;
    const errors = this.window.filter((ok) => !ok).length;
    if (errors / this.window.length > ERROR_RATE_LIMIT) {
      if (!this.rateDegraded) {
        this.rateDegraded = true;
        this.degrade();
      }
    } else {
      this.rateDegraded = false;
    }
  }

  private degrade(): void {
    if (this.level < INTERVALS_MS.length - 1) this.level += 1;
    this.cleanTicks = 0;
  }

  currentLevel(): number {
    return this.level;
  }

  intervalMs(): number {
    const now = Date.now();
    if (now < this.retryUntil) {
      // Retry-After 生效期内：直接遵守上游要求的剩余等待时间
      return this.retryUntil - now;
    }
    return INTERVALS_MS[this.level] ?? INTERVALS_MS[INTERVALS_MS.length - 1]!;
  }

  treeBudget(): number {
    return TREE_BUDGETS[this.level] ?? TREE_BUDGETS[TREE_BUDGETS.length - 1]!;
  }
}

export const hnHealth = new HnHealth();
