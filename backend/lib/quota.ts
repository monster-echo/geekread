import { env } from './env';
import { reserveTranslation } from './quota-store';

export function limitFor(isPro: boolean): number {
  return isPro ? env().proDailyTranslations : env().freeDailyTranslations;
}

export function today(): string {
  return new Date().toISOString().slice(0, 10);
}

export async function reserveDaily(day: string, clientId: string, isPro: boolean) {
  return reserveTranslation(day, clientId, limitFor(isPro));
}
