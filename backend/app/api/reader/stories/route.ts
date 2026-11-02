import { fetchStories } from '../../../../lib/hacker-news';
import { blockedIdsForItems } from '../../../../lib/content-filter';
import { errorResponse, json, safeErrorStatus } from '../../../../lib/http';

export async function GET(request: Request): Promise<Response> {
  const type = new URL(request.url).searchParams.get('type');
  if (type !== 'top' && type !== 'latest') return errorResponse('invalid_request', 400);
  try {
    const data = await fetchStories(type);
    // 出站过滤：黑名单 + 审核命中的 story 不下发
    const blocked = await blockedIdsForItems(data.items, 'story');
    const items = data.items.filter((item) => !blocked.has(Number(item.id)));
    return json({ ...data, items, ...(blocked.size > 0 ? { blocked: blocked.size } : {}) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, safeErrorStatus(message));
  }
}
