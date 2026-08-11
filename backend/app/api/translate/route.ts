import { hasProEntitlement } from '../../../lib/entitlement.js';
import { errorResponse, json, requireString, safeErrorStatus } from '../../../lib/http.js';
import { translateWithModel } from '../../../lib/model.js';
import { reserveDaily, today } from '../../../lib/quota.js';
import { cacheTranslation, getCachedTranslation } from '../../../lib/storage.js';

const SUPPORTED = new Set(['en', 'ja', 'ko', 'zh-Hans', 'zh-Hant']);
const MAX_ENTRIES = 20;
const MAX_TOTAL_CHARS = 12_000;

type Entry = { key: string; text: string };
type Result = { key: string; translation?: string; cached?: boolean; error?: string };

export async function POST(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0 || installId.length > 128) {
    return errorResponse('invalid_request', 400);
  }
  const clientId: string = installId;
  const auth = request.headers.get('authorization') ?? '';
  const bearer = /^Bearer\s+(.+)$/i.exec(auth)?.[1];
  const isPro = bearer ? hasProEntitlement(bearer.trim()) : false;

  let payload: unknown;
  try { payload = await request.json(); } catch { return errorResponse('invalid_request', 400); }

  try {
    const targetLanguage = requireString((payload as { targetLanguage?: unknown }).targetLanguage, 20);
    if (!SUPPORTED.has(targetLanguage)) throw new Error('unsupported_target_language');
    const rawEntries = (payload as { entries?: unknown }).entries;
    if (!Array.isArray(rawEntries) || rawEntries.length === 0 || rawEntries.length > MAX_ENTRIES) {
      throw new Error('invalid_request');
    }
    const entries: Entry[] = rawEntries.map((v) => {
      if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Error('invalid_request');
      const e = v as { key?: unknown; text?: unknown };
      return { key: requireString(e.key, 256), text: requireString(e.text, 12_000) };
    });
    if (entries.reduce((n, e) => n + e.text.length, 0) > MAX_TOTAL_CHARS) throw new Error('invalid_request');

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
          const cached = await getCachedTranslation(entry.text, targetLanguage);
          if (cached) { results[index] = { key: entry.key, translation: cached, cached: true }; continue; }
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

    await Promise.all(Array.from({ length: Math.min(4, entries.length) }, () => worker()));
    return json({ results, ...(remaining === undefined ? {} : { remainingTranslations: remaining }) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, safeErrorStatus(message));
  }
}
