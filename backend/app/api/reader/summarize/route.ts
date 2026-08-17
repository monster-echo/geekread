import { errorResponse, json, requireString, safeErrorStatus } from '../../../../lib/http';
import { summarizeWithModel } from '../../../../lib/model';
import { cacheSummary, getCachedSummary } from '../../../../lib/cache-store';

const SUPPORTED = new Set(['en', 'ja', 'ko', 'zh-Hans', 'zh-Hant', 'ms', 'id', 'th', 'vi', 'ar']);
const MAX_TITLE = 300;
const MAX_BODY = 4000;
const MAX_COMMENTS = 3;
const MAX_COMMENT = 500;

export async function POST(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0 || installId.length > 128) {
    return errorResponse('invalid_request', 400);
  }

  let payload: unknown;
  try { payload = await request.json(); } catch { return errorResponse('invalid_request', 400); }

  try {
    const targetLanguage = requireString((payload as { targetLanguage?: unknown }).targetLanguage, 20);
    if (!SUPPORTED.has(targetLanguage)) throw new Error('unsupported_target_language');
    const storyId = (payload as { storyId?: unknown }).storyId;
    if (typeof storyId !== 'number' || !Number.isSafeInteger(storyId) || storyId <= 0) {
      throw new Error('invalid_request');
    }
    const title = requireString((payload as { title?: unknown }).title, MAX_TITLE);
    const body = (payload as { text?: unknown }).text;
    const bodyText = typeof body === 'string' ? body.slice(0, MAX_BODY) : '';
    const rawComments = (payload as { comments?: unknown }).comments;
    if (!Array.isArray(rawComments) || rawComments.length > MAX_COMMENTS) throw new Error('invalid_request');
    const comments: string[] = rawComments.map((v) => requireString(v, MAX_COMMENT));

    const cached = await getCachedSummary(storyId, targetLanguage);
    if (cached) return json({ summary: cached, cached: true });

    const summary = await summarizeWithModel(title, bodyText, comments, targetLanguage);
    await cacheSummary(storyId, targetLanguage, summary);
    return json({ summary });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, safeErrorStatus(message));
  }
}
