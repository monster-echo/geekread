// backend/app/api/reader/warm/route.ts
import { errorResponse, json } from '../../../../lib/http';
import { readStoryList } from '../../../../lib/hn-store';
import { tick, warmLists, warmStoryHeaders, warmTrees } from '../../../../lib/sync';

/**
 * 缓存预热（手动触发）：列表 + 文章头 + 评论树全量一轮。
 * 生产由内置调度器每分钟自动跑；此接口供运维手动触发/验证。
 * 需带 ?token= 校验，避免被外部滥用拉取 HN。?full=1 提高树预算到 30。
 */
export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get('token');
  const expected = process.env.WARM_CACHE_TOKEN?.trim();
  if (expected && token !== expected) return errorResponse('forbidden', 403);

  try {
    if (url.searchParams.get('full') !== '1') {
      return json({ ok: true, ...(await tick()) });
    }
    const lists = await warmLists();
    const merged: number[] = [];
    const seen = new Set<number>();
    const tl = await readStoryList('top');
    const lt = await readStoryList('latest');
    for (const id of [...(tl?.ids ?? []), ...(lt?.ids ?? [])]) {
      if (!seen.has(id)) { seen.add(id); merged.push(id); }
    }
    const grown = await warmStoryHeaders(merged.slice(0, 30));
    const trees = await warmTrees(grown, 30);
    return json({ ok: true, lists, headers: Math.min(merged.length, 30), trees });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, 500);
  }
}
