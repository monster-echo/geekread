import { fetchItems } from '../../../../lib/hacker-news';
import { blockedIdsForItems } from '../../../../lib/content-filter';
import { errorResponse, json, requireIds, safeErrorStatus } from '../../../../lib/http';

export async function POST(request: Request): Promise<Response> {
  let payload: unknown;
  try { payload = await request.json(); } catch { return errorResponse('invalid_request', 400); }
  try {
    const ids = requireIds((payload as { ids?: unknown }).ids);
    const data = await fetchItems(ids);
    // 出站过滤：被下架的 story/comment 以 null 返回（与"HN 已删除"语义一致，客户端会跳过）
    const blocked = await blockedIdsForItems(data.items, 'story');
    let count = 0;
    const items = data.items.map((item) => {
      if (!item) return null;
      if (blocked.has(Number(item.id))) {
        count += 1;
        return null;
      }
      return item;
    });
    return json({ ...data, items, ...(count > 0 ? { blocked: count } : {}) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, safeErrorStatus(message));
  }
}
