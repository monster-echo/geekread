import { hasProEntitlement } from '../../../../lib/entitlement';
import { errorResponse, json } from '../../../../lib/http';
import { limitFor, today } from '../../../../lib/quota';
import { peekTranslation } from '../../../../lib/quota-store';

export async function GET(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0 || installId.length > 128) {
    return errorResponse('invalid_request', 400);
  }
  const auth = request.headers.get('authorization') ?? '';
  const bearer = /^Bearer\s+(.+)$/i.exec(auth)?.[1];
  const isPro = bearer ? hasProEntitlement(bearer.trim()) : false;
  const limit = limitFor(isPro);
  const used = await peekTranslation(today(), installId);
  return json({ used, limit, remaining: Math.max(0, limit - used), isPro });
}
