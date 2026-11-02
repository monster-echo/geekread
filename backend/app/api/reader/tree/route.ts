import { errorResponse, json } from '../../../../lib/http';
import { fetchCommentTree } from '../../../../lib/hacker-news';
import { blockedIdsForItems, isStoryBlocked } from '../../../../lib/content-filter';

/**
 * POST /api/reader/tree { storyId }
 *
 * 服务端一次解析整棵评论树：Algolia /items/{storyId} 单请求返回完整嵌套树，
 * 递归展平为扁平评论列表（不含 story 本身），取代旧的逐层 BFS（冷缓存下 N+1 次上游请求）。
 * 返回扁平评论列表，与 /api/reader/items 结构一致。
 */
export async function POST(request: Request): Promise<Response> {
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return errorResponse('invalid_request', 400);
  }
  const storyId = Number((payload as { storyId?: unknown }).storyId);
  if (!Number.isInteger(storyId) || storyId <= 0) {
    return errorResponse('invalid_request', 400);
  }

  try {
    // story 被下架：整棵树不下发（返回空树 + blocked 标记，避免客户端整页报错）
    if (await isStoryBlocked(storyId)) {
      return json({ items: [], cached: false, stale: false, blocked: true });
    }
    const data = await fetchCommentTree(storyId);
    // 出站过滤：被下架的评论移除；其子评论因父节点缺失自然不渲染
    const blocked = await blockedIdsForItems(data.items, 'comment');
    const items = data.items.filter((item) => !blocked.has(Number(item.id)));
    return json({ ...data, items, ...(blocked.size > 0 ? { blocked: blocked.size } : {}) });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, 500);
  }
}
