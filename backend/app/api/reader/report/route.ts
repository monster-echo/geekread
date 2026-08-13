import { errorResponse, json } from '../../../../lib/http';
import { redis } from '../../../../lib/storage';

const REASONS = new Set(['false_info', 'nsfw', 'spam', 'illegal', 'other']);

/**
 * POST /api/reader/report { storyId, commentId, reason, text? }
 *
 * 内容举报：接收 HN 评论的举报并存入 Redis 列表（geekread:reports）。
 * 用于内容合规（UGC 评论 + AI 翻译场景下的违规反馈入口）。
 */
export async function POST(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0) {
    return errorResponse('invalid_request', 400);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return errorResponse('invalid_request', 400);
  }
  const storyId = Number((payload as { storyId?: unknown }).storyId);
  const commentId = Number((payload as { commentId?: unknown }).commentId);
  const reason = String((payload as { reason?: unknown }).reason ?? '');
  if (!Number.isInteger(storyId) || !Number.isInteger(commentId) || !REASONS.has(reason)) {
    return errorResponse('invalid_request', 400);
  }
  const raw = (payload as { text?: unknown }).text;
  const text = typeof raw === 'string' ? raw.slice(0, 500) : '';

  const entry = JSON.stringify({ storyId, commentId, reason, text, installId, ts: Date.now() });
  const client = await redis();
  if (client) {
    await client.rPush('geekread:reports', entry);
  }
  return json({ ok: true });
}
