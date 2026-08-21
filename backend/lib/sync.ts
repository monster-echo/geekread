// backend/lib/sync.ts
import { fetchItemRaw, ITEM_FRESH_SECONDS, pullStoryList, pullTree } from './hacker-news';
import { oldestFetchedStories, readItems, readStoryList, upsertItems } from './hn-store';
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
    pullStoryList('top', TOP_N),
    pullStoryList('latest', LATEST_N),
  ]);
  return { top: top.ids.length, latest: latest.ids.length };
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
        fresh = await fetchItemRaw(id) as { descendants?: unknown } | null;
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
 * 每棵树用 pullTree 一次整树拉取（Algolia /items/{id} 嵌套树）并落库，取代逐层 BFS。
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
      await pullTree(storyId);
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
