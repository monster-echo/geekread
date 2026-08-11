import { fetchItems } from '../../../../lib/hacker-news.js';
import { errorResponse, json, requireIds, safeErrorStatus } from '../../../../lib/http.js';

export async function POST(request: Request): Promise<Response> {
  let payload: unknown;
  try { payload = await request.json(); } catch { return errorResponse('invalid_request', 400); }
  try {
    const ids = requireIds((payload as { ids?: unknown }).ids);
    return json(await fetchItems(ids));
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, safeErrorStatus(message));
  }
}
