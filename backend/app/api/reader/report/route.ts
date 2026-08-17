// backend/app/api/reader/report/route.ts
import { errorResponse, json } from '../../../../lib/http';
import { saveReport } from '../../../../lib/report-store';

const REASONS = new Set(['false_info', 'nsfw', 'spam', 'illegal', 'other']);

/**
 * POST /api/reader/report { storyId, commentId, reason, text? }
 *
 * 内容举报：接收 HN 评论的举报并落库（Postgres Report 表）。
 */
export async function POST(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0) {
    return errorResponse('invalid_request', 400);
  }

  let payload: unknown;
  try { payload = await request.json(); } catch { return errorResponse('invalid_request', 400); }

  const storyId = Number((payload as { storyId?: unknown }).storyId);
  const commentId = Number((payload as { commentId?: unknown }).commentId);
  const reason = String((payload as { reason?: unknown }).reason ?? '');
  if (!Number.isInteger(storyId) || !Number.isInteger(commentId) || !REASONS.has(reason)) {
    return errorResponse('invalid_request', 400);
  }
  const raw = (payload as { text?: unknown }).text;
  const text = typeof raw === 'string' ? raw.slice(0, 500) : '';

  try {
    await saveReport({ storyId, commentId, reason, text, installId, ts: Date.now() });
  } catch {
    // 落库失败不阻断用户反馈（旧版 Redis 失败同样静默）
  }
  return json({ ok: true });
}
