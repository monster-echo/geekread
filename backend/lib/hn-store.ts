// backend/lib/hn-store.ts
import { db } from './db';

/** HN 原始 item（null = HN 返回 null：已删除/不存在） */
export type HnRawItem = Record<string, unknown> | null;
export type ItemUpsert = { id: number; raw: HnRawItem };
export type ItemRow = { id: number; raw: HnRawItem; missing: boolean; fetchedAt: Date };

// ---- 内存回退（dev/test 无 DATABASE_URL；语义对齐旧 storage.ts）----
const memItems = new Map<number, { raw: HnRawItem; fetchedAt: Date }>();
const memLists = new Map<string, { ids: number[]; fetchedAt: Date }>();

/** PG upsert 分片大小：避免单事务过大长期占用连接 */
const UPSERT_BATCH = 100;

/** HN raw JSON → HnItem 行字段（缺省 undefined 交由 Prisma 忽略） */
function rowFields(raw: HnRawItem) {
  if (raw === null) return { missing: true };
  const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined);
  const int = (v: unknown): number | undefined =>
    typeof v === 'number' && Number.isSafeInteger(v) ? v : undefined;
  const kids = Array.isArray(raw.kids)
    ? raw.kids.filter((k): k is number => typeof k === 'number' && Number.isSafeInteger(k))
    : [];
  return {
    type: str(raw.type),
    by: str(raw.by),
    time: int(raw.time),
    text: str(raw.text),
    url: str(raw.url),
    title: str(raw.title),
    score: int(raw.score),
    descendants: int(raw.descendants),
    kids,
    deleted: raw.deleted === true,
    dead: raw.dead === true,
    missing: false,
    raw: raw as object,
  };
}

export async function upsertItems(items: ItemUpsert[]): Promise<void> {
  if (items.length === 0) return;
  const client = await db();
  if (!client) {
    const now = new Date();
    for (const it of items) memItems.set(it.id, { raw: it.raw, fetchedAt: now });
    return;
  }
  const now = new Date();
  for (let i = 0; i < items.length; i += UPSERT_BATCH) {
    const batch = items.slice(i, i + UPSERT_BATCH);
    await client.$transaction(
      batch.map((it) =>
        client.hnItem.upsert({
          where: { id: it.id },
          create: { id: it.id, fetchedAt: now, ...rowFields(it.raw) },
          update: { fetchedAt: now, ...rowFields(it.raw) },
        }),
      ),
    );
  }
}

export async function readItems(ids: number[]): Promise<Map<number, ItemRow>> {
  if (ids.length === 0) return new Map();
  const unique = [...new Set(ids)];
  const client = await db();
  if (!client) {
    const out = new Map<number, ItemRow>();
    for (const id of unique) {
      const hit = memItems.get(id);
      if (hit) out.set(id, { id, raw: hit.raw, missing: hit.raw === null, fetchedAt: hit.fetchedAt });
    }
    return out;
  }
  const rows = await client.hnItem.findMany({ where: { id: { in: unique } } });
  const out = new Map<number, ItemRow>();
  for (const r of rows) {
    out.set(r.id, {
      id: r.id,
      raw: r.missing ? null : (r.raw as HnRawItem),
      missing: r.missing,
      fetchedAt: r.fetchedAt,
    });
  }
  return out;
}

export async function readStoryList(type: string): Promise<{ ids: number[]; fetchedAt: Date } | undefined> {
  const client = await db();
  if (!client) {
    const hit = memLists.get(type);
    return hit ? { ids: hit.ids, fetchedAt: hit.fetchedAt } : undefined;
  }
  const row = await client.storyList.findUnique({ where: { type } });
  return row ? { ids: row.ids, fetchedAt: row.fetchedAt } : undefined;
}

export async function saveStoryList(type: string, ids: number[]): Promise<void> {
  const now = new Date();
  const client = await db();
  if (!client) {
    memLists.set(type, { ids, fetchedAt: now });
    return;
  }
  await client.storyList.upsert({
    where: { type },
    create: { type, ids, fetchedAt: now },
    update: { ids, fetchedAt: now },
  });
}

/** 树轮转候选：type=story 且 fetchedAt 早于 minAgeMinutes 的，最老优先。 */
export async function oldestFetchedStories(limit: number, minAgeMinutes: number): Promise<number[]> {
  const cutoff = new Date(Date.now() - minAgeMinutes * 60_000);
  const client = await db();
  if (!client) {
    return [...memItems.entries()]
      .filter(([, v]) => v.raw !== null && (v.raw as { type?: unknown })?.type === 'story' && v.fetchedAt < cutoff)
      .sort((a, b) => a[1].fetchedAt.getTime() - b[1].fetchedAt.getTime())
      .slice(0, limit)
      .map(([id]) => id);
  }
  const rows = await client.hnItem.findMany({
    where: { type: 'story', missing: false, fetchedAt: { lt: cutoff } },
    orderBy: { fetchedAt: 'asc' },
    take: limit,
    select: { id: true },
  });
  return rows.map((r) => r.id);
}

/** 仅测试用：把某 id 的 fetchedAt 回拨（验证 SWR 过期逻辑）。 */
export async function __testBackdateItem(id: number, minutesAgo: number): Promise<void> {
  const client = await db();
  if (!client) {
    const hit = memItems.get(id);
    if (hit) hit.fetchedAt = new Date(Date.now() - minutesAgo * 60_000);
    return;
  }
  await client.hnItem.update({
    where: { id },
    data: { fetchedAt: new Date(Date.now() - minutesAgo * 60_000) },
  });
}
