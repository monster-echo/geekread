import { hasProEntitlement } from '../../../../lib/entitlement';
import { errorResponse, json } from '../../../../lib/http';
import { today, topicLimitFor } from '../../../../lib/quota';
import { peekTranslation } from '../../../../lib/quota-store';

export async function GET(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0 || installId.length > 128) {
    return errorResponse('invalid_request', 400);
  }
  const auth = request.headers.get('authorization') ?? '';
  const bearer = /^Bearer\s+(.+)$/i.exec(auth)?.[1];
  const isPro = bearer ? hasProEntitlement(bearer.trim()) : false;
  // used/limit/remaining 现在的口径是"可翻译的 topic 篇数"（QuotaUsage.used 按 topic 计）
  const limit = topicLimitFor(isPro);
  const used = await peekTranslation(today(), installId);
  return json({ used, limit, remaining: Math.max(0, limit - used), isPro });
}
