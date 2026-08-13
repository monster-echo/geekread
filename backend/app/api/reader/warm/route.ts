import { fetchStoryIds, fetchItems } from '../../../../lib/hacker-news';
import { errorResponse, json } from '../../../../lib/http';

/**
 * 缓存预热：定时拉取热门/最新列表 + 前 N 篇文章写入缓存。
 * 由服务器 cron 每小时触发（curl 本接口），用户首启即命中缓存、秒开。
 * 需带 ?token= 校验，避免被外部滥用拉取 HN。
 */
export async function GET(request: Request): Promise<Response> {
  const token = new URL(request.url).searchParams.get('token');
  const expected = process.env.WARM_CACHE_TOKEN?.trim();
  if (expected && token !== expected) return errorResponse('forbidden', 403);

  try {
    const [top, latest] = await Promise.all([fetchStoryIds('top'), fetchStoryIds('latest')]);
    const merged: number[] = [];
    const seen: Set<number> = new Set<number>();
    for (const id of [...top.ids, ...latest.ids]) {
      if (!seen.has(id)) { seen.add(id); merged.push(id); }
    }
    await fetchItems(merged.slice(0, 30));
    return json({ ok: true, warmed: Math.min(merged.length, 30), cached: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, 500);
  }
}
