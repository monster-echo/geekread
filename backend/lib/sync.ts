// backend/lib/sync.ts
import { fetchItems, fetchJson, ITEM_FRESH_SECONDS } from './hacker-news';
import { oldestFetchedStories, readItems, readStoryList, saveStoryList, upsertItems } from './hn-store';
import { hnHealth } from './hn-health';

const TOP_N = Number(process.env.WARM_TOP_N ?? 50);
const LATEST_N = Number(process.env.WARM_LATEST_N ?? 50);
const TREE_N = Number(process.env.WARM_TREE_N ?? 30);
/** 轮转补刷的最小树龄（分钟）：刚刷过的树不重复进入轮转 */
const TREE_ROTATE_MIN_AGE_MINUTES = 30;

export type TickResult = {
  lists: { top: number; latest: number };
  headers: number;
  trees: number;
  errors: number;
};

/** 列表层：拉 top/latest 列表并保存。 */
export async function warmLists(): Promise<{ top: number; latest: number }> {
  const [top, latest] = await Promise.all([
    fetchJson<number[]>('/topstories.json'),
    fetchJson<number[]>('/newstories.json'),
  ]);
  await saveStoryList('top', top.slice(0, TOP_N));
  await saveStoryList('latest', latest.slice(0, LATEST_N));
  return { top: Math.min(top.length, TOP_N), latest: Math.min(latest.length, LATEST_N) };
}

/**
 * 文章头层：拉列表头部文章本体并 upsert（fetchItems 内部 fresh 直返/未落库回源）。
 * 返回 descendants 增长了的文章 id（树层增量触发依据）。
 */
export async function warmStoryHeaders(ids: number[]): Promise<number[]> {
  if (ids.length === 0) return [];
  const before = await readItems(ids);
  const grown: number[] = [];
  const CONCURRENCY = 8;
  let nextIndex = 0;
  async function worker(): Promise<void> {
    while (nextIndex < ids.length) {
      const id = ids[nextIndex++]!;
      const old = before.get(id);
      const ageSeconds = old ? (Date.now() - old.fetchedAt.getTime()) / 1000 : Infinity;
      let fresh: { descendants?: unknown } | null | undefined;
      if (old && ageSeconds <= ITEM_FRESH_SECONDS) {
        // fresh：跳过网络（增量语义——刚刷过的头不重复拉）
        fresh = old.raw as { descendants?: unknown } | null;
      } else {
        // 未落库或超 fresh：同步回源一次并 upsert
        fresh = await fetchJson(`/item/${id}.json`) as { descendants?: unknown } | null;
        if (fresh !== null && typeof fresh !== 'object') throw new Error('hacker_news_invalid_response');
        await upsertItems([{ id, raw: fresh }]);
      }
      const oldDesc = typeof (old?.raw as { descendants?: unknown } | null | undefined)?.descendants === 'number'
        ? (old!.raw as { descendants: number }).descendants : undefined;
      const newDesc = typeof fresh?.descendants === 'number' ? fresh.descendants : undefined;
      if (oldDesc !== undefined && newDesc !== undefined && newDesc > oldDesc) grown.push(id);
    }
  }
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, ids.length) }, () => worker()));
  grown.sort((a, b) => ids.indexOf(a) - ids.indexOf(b));
  return grown;
}

/**
 * 评论树层：候选 = descendants 增长的树 + 轮转最老树；每 tick 预算上限。
 * 树内条目走 fetchItems（fresh 的自动命中本地，天然增量）。
 */
export async function warmTrees(grown: number[], budget: number): Promise<number> {
  if (budget <= 0) return 0;
  const rotated = await oldestFetchedStories(budget, TREE_ROTATE_MIN_AGE_MINUTES);
  const seen = new Set<number>();
  const candidates: number[] = [];
  for (const id of [...grown, ...rotated]) {
    if (!seen.has(id)) { seen.add(id); candidates.push(id); }
  }
  let synced = 0;
  for (const storyId of candidates.slice(0, budget)) {
    try {
      const storyRows = await readItems([storyId]);
      const story = storyRows.get(storyId)?.raw as { kids?: unknown } | null | undefined;
      const frontier: number[] = Array.isArray(story?.kids)
        ? (story!.kids as unknown[]).filter((k): k is number => typeof k === 'number')
        : [];
      const seenIds = new Set<number>([storyId]);
      let visited = 0;
      while (frontier.length > 0 && visited < 200) {
        const batch = frontier.splice(0, 50);
        const res = await fetchItems(batch);
        for (const item of res.items) {
          if (item === null) continue;
          const id = Number(item.id);
          if (!id || seenIds.has(id)) continue;
          seenIds.add(id);
          visited += 1;
          const kids = Array.isArray(item.kids)
            ? item.kids.filter((k): k is number => typeof k === 'number') : [];
          for (const k of kids) if (visited < 200) frontier.push(k);
        }
      }
      synced += 1;
    } catch {
      // 单棵树失败不影响其他树
    }
  }
  return synced;
}

/** 调度器每 tick 入口。 */
export async function tick(): Promise<TickResult> {
  hnHealth.noteTickStart();
  let errors = 0;
  let lists = { top: 0, latest: 0 };
  try {
    lists = await warmLists();
  } catch { errors += 1; }

  const top = await readStoryList('top');
  const latest = await readStoryList('latest');
  const headerIds = [...new Set([...(top?.ids.slice(0, TREE_N) ?? []), ...(latest?.ids.slice(0, TREE_N) ?? [])])];
  let grown: number[] = [];
  try {
    grown = await warmStoryHeaders(headerIds);
  } catch { errors += 1; }

  let trees = 0;
  try {
    trees = await warmTrees(grown, hnHealth.treeBudget());
  } catch { errors += 1; }

  if (errors === 0) hnHealth.noteTickClean();
  return { lists, headers: headerIds.length, trees, errors };
}
