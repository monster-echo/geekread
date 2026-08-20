import { hasProEntitlement } from '../../../lib/entitlement';
import { errorResponse, json, safeErrorStatus } from '../../../lib/http';
import { translateWithModel } from '../../../lib/model';
import { reserveDaily, today } from '../../../lib/quota';
import { cacheTranslation, getCachedTranslation } from '../../../lib/cache-store';

const SUPPORTED = new Set(['en', 'ja', 'ko', 'zh-Hans', 'zh-Hant', 'ms', 'id', 'th', 'vi', 'ar']);
const MAX_ENTRIES = 20;
const MAX_TOTAL_CHARS = 12_000;

type Entry = { key: string; text: string };
type Result = { key: string; translation?: string; cached?: boolean; error?: string };

export async function POST(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0 || installId.length > 128) {
    console.log('[translate] REJECT: installId missing/invalid');
    return errorResponse('invalid_request', 400);
  }
  const clientId: string = installId;
  const auth = request.headers.get('authorization') ?? '';
  const bearer = /^Bearer\s+(.+)$/i.exec(auth)?.[1];
  const isPro = bearer ? hasProEntitlement(bearer.trim()) : false;

  let payload: unknown;
  try { payload = await request.json(); } catch { console.log('[translate] REJECT: json parse'); return errorResponse('invalid_request', 400); }

  try {
    const rawLang = (payload as { targetLanguage?: unknown }).targetLanguage;
    if (typeof rawLang !== 'string' || rawLang.trim().length === 0) {
      throw new Error('invalid_request: targetLanguage missing');
    }
    if (rawLang.length > 20) throw new Error('invalid_request: targetLanguage too long');
    const targetLanguage = rawLang.trim();
    if (!SUPPORTED.has(targetLanguage)) throw new Error('unsupported_target_language');
    // free=true 走免费通道（不扣配额）：列表标题/详情正文，用于留存。
    const isFree = (payload as { free?: unknown }).free === true;
    const rawEntries = (payload as { entries?: unknown }).entries;
    if (!Array.isArray(rawEntries) || rawEntries.length === 0) {
      throw new Error('invalid_request: entries missing or empty');
    }
    if (rawEntries.length > MAX_ENTRIES) {
      throw new Error(`invalid_request: too many entries (${rawEntries.length} > ${MAX_ENTRIES})`);
    }
    const entries: Entry[] = rawEntries.map((v) => {
      if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Error('invalid_request: entry not an object');
      const e = v as { key?: unknown; text?: unknown };
      // 空文本不再 400 整批（链接/图片型评论 HTML 清洗后为空）：按条目返回空翻译，
      // 不调 LLM 不扣配额——保护老版本客户端的整批请求不被一条空评论毒死。
      const text = typeof e.text === 'string' ? e.text.trim().slice(0, 12_000) : null;
      if (text === null) throw new Error('invalid_request: entry text not a string');
      const key = typeof e.key === 'string' && e.key.trim().length > 0 && e.key.length <= 256 ? e.key.trim() : null;
      if (key === null) throw new Error('invalid_request: entry key missing');
      return { key, text };
    });
    if (entries.reduce((n, e) => n + e.text.length, 0) > MAX_TOTAL_CHARS) {
      throw new Error(`invalid_request: total chars exceed ${MAX_TOTAL_CHARS}`);
    }

    const day = today();
    const results: Result[] = new Array(entries.length);
    let remaining: number | undefined;
    let nextIndex = 0;

    async function worker(): Promise<void> {
      while (nextIndex < entries.length) {
        const index = nextIndex++;
        const entry = entries[index];
        if (!entry) return;
        try {
          if (entry.text.length === 0) {
            results[index] = { key: entry.key, translation: '', cached: true };
            continue;
          }
          const cached = await getCachedTranslation(entry.text, targetLanguage);
          if (cached) { results[index] = { key: entry.key, translation: cached, cached: true }; continue; }
          if (isFree) {
            // 免费通道：不扣配额
            try {
              const translation = await translateWithModel(entry.text, targetLanguage);
              await cacheTranslation(entry.text, targetLanguage, translation);
              results[index] = { key: entry.key, translation };
            } catch (error) {
              results[index] = { key: entry.key, error: error instanceof Error ? error.message : 'translation_failed' };
            }
            continue;
          }
          const reservation = await reserveDaily(day, clientId, isPro);
          if (!reservation.allowed) { results[index] = { key: entry.key, error: 'quota_exceeded' }; remaining = 0; continue; }
          remaining = remaining === undefined ? reservation.remaining : Math.min(remaining, reservation.remaining);
          try {
            const translation = await translateWithModel(entry.text, targetLanguage);
            await cacheTranslation(entry.text, targetLanguage, translation);
            results[index] = { key: entry.key, translation };
          } catch (error) {
            await reservation.rollback();
            results[index] = { key: entry.key, error: error instanceof Error ? error.message : 'translation_failed' };
          }
        } catch (error) {
          results[index] = { key: entry.key, error: error instanceof Error ? error.message : 'translation_failed' };
        }
      }
    }

    // 并发 8：20 条/批 × 单条 ~3.8s，4 并发要 ~19s 会触发客户端 15s 超时；8 并发 ~11s
  await Promise.all(Array.from({ length: Math.min(8, entries.length) }, () => worker()));
    return json({ results, ...(remaining === undefined ? {} : { remainingTranslations: remaining }) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    // 临时诊断：打印失败请求摘要，定位 invalid_request 具体来源
    const p = payload as { targetLanguage?: unknown; entries?: unknown; free?: unknown } | null;
    const entryCount = Array.isArray(p?.entries) ? (p.entries as unknown[]).length : 'not-array';
    const totalChars = Array.isArray(p?.entries)
      ? (p.entries as { text?: unknown }[]).reduce((n, e) => n + (typeof e?.text === 'string' ? e.text.length : 0), 0)
      : -1;
    console.log(`[translate] REJECT: ${message} | targetLanguage=${JSON.stringify(p?.targetLanguage)} free=${JSON.stringify(p?.free)} entries=${entryCount} totalChars=${totalChars}`);
    return errorResponse(message, safeErrorStatus(message));
  }
}
