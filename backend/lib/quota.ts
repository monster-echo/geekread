import { env } from './env';
import { reserveTranslation } from './quota-store';

/// 每日可翻译 topic 数（新模型）
export function topicLimitFor(isPro: boolean): number {
  return isPro ? env().proDailyTopics : env().freeDailyTopics;
}

/// legacy 按条配额（旧客户端无 storyId 时使用）
export function limitFor(isPro: boolean): number {
  return isPro ? env().proDailyTranslations : env().freeDailyTranslations;
}

export function today(): string {
  return new Date().toISOString().slice(0, 10);
}

export async function reserveDaily(day: string, clientId: string, isPro: boolean) {
  return reserveTranslation(day, clientId, limitFor(isPro));
}
