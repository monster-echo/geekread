export type Env = {
  modelApiUrl: string;
  modelApiKey: string;
  modelName: string;
  freeDailyTranslations: number;
  proDailyTranslations: number;
  entitlementSigningSecret: string;
  hackerNewsApiUrl: string;
};

function num(name: string, fallback: number): number {
  const raw = process.env[name]?.trim();
  const parsed = raw ? Number(raw) : fallback;
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

function str(name: string, fallback = ''): string {
  return process.env[name]?.trim() || fallback;
}

let cached: Env | undefined;
export function reloadEnv(): Env {
  cached = {
    modelApiUrl: str('MODEL_API_URL'),
    modelApiKey: str('MODEL_API_KEY'),
    modelName: str('MODEL_NAME'),
    freeDailyTranslations: num('FREE_DAILY_TRANSLATIONS', 20),
    proDailyTranslations: num('PRO_DAILY_TRANSLATIONS', 500),
    entitlementSigningSecret: str('ENTITLEMENT_SIGNING_SECRET'),
    hackerNewsApiUrl: str('HACKER_NEWS_API_URL', 'https://hn.algolia.com/api/v1'),
  };
  return cached;
}
export function env(): Env {
  return cached ?? reloadEnv();
}
