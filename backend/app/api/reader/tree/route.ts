import { errorResponse, json } from '../../../../lib/http';
import { fetchItems } from '../../../../lib/hacker-news';

const MAX_COMMENTS = 200;
const MAX_BATCH = 50;

type HnItem = {
  id?: unknown;
  kids?: unknown;
};

/**
 * POST /api/reader/tree { storyId }
 *
 * 服务端一次请求解析整棵评论树：内部按层连续用并发 20 拉取，
 * 避免前端逐层往返（每层一次 HTTP 往返 + 一次 HN 拉取）。
 * 返回扁平评论列表（不含 story 本身），与 /api/reader/items 结构一致。
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

  const storyRes = await fetchItems([storyId]);
  const story = storyRes.items[0] as (HnItem & { kids?: number[] }) | null;
  if (story === null) {
    return json({ items: [], cached: storyRes.cached === true, stale: storyRes.stale === true });
  }

  const all: Record<number, unknown> = {};
  let count = 0;
  let frontier: number[] = Array.isArray(story.kids) ? story.kids.slice(0, MAX_COMMENTS) : [];
  let cached = storyRes.cached === true;
  let stale = storyRes.stale === true;

  while (frontier.length > 0 && count < MAX_COMMENTS) {
    const batch = frontier.slice(0, MAX_BATCH);
    frontier = frontier.slice(MAX_BATCH);
    const res = await fetchItems(batch);
    if (res.cached !== true) cached = false;
    if (res.stale === true) stale = true;

    for (const item of res.items) {
      if (item === null) continue;
      const id = Number((item as HnItem).id);
      if (!id || all[id] !== undefined) continue;
      all[id] = item;
      count += 1;
      const kids = Array.isArray((item as HnItem).kids) ? (item as { kids: number[] }).kids : [];
      for (const k of kids) {
        if (count < MAX_COMMENTS) frontier.push(k);
      }
    }
  }

  return json({ items: Object.values(all), cached, stale });
}
