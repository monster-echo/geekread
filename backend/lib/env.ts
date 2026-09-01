export type Env = {
  modelApiUrl: string;
  modelApiKey: string;
  modelName: string;
  /// 免费/Pro 每日可翻译 topic（story）篇数
  freeDailyTopics: number;
  proDailyTopics: number;
  /// 每篇 topic 每日翻译请求批数上限（防超高楼帖子烧 LLM 成本）
  topicRequestCap: number;
  /// 旧版按条计费的配额（无 storyId 的 legacy 请求仍按条），与新版二选一
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
    freeDailyTopics: num('FREE_DAILY_TOPICS', num('FREE_DAILY_TRANSLATIONS', 30)),
    proDailyTopics: num('PRO_DAILY_TOPICS', num('PRO_DAILY_TRANSLATIONS', 200)),
    topicRequestCap: num('TOPIC_REQUEST_CAP', 40),
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
