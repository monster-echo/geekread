// backend/lib/blocklist.ts
//
// 内容黑名单（人工/审核服务判定的违规内容）：按 HN item id 记录 story/comment。
// 出站层（stories/items/tree/translate/summarize）优先查黑名单，命中即不下发。
// dev/test 无 DATABASE_URL 时走内存回退（与 report-store / cache-store 一致）。

import { db } from './db';

export type BlockKind = 'story' | 'comment';

export type BlockRecord = {
  kind: BlockKind;
  targetId: number;
  reason: string;
  /** 来源：manual（人工）/ report（举报处置）/ auto（审核服务） */
  source: string;
  createdAt: number;
};

const memBlocks = new Map<string, BlockRecord>();

function memKey(kind: BlockKind, targetId: number): string {
  return `${kind}:${targetId}`;
}

export function isBlockKind(value: unknown): value is BlockKind {
  return value === 'story' || value === 'comment';
}

export async function addBlock(input: {
  kind: BlockKind;
  targetId: number;
  reason?: string;
  source?: string;
}): Promise<BlockRecord> {
  const record: BlockRecord = {
    kind: input.kind,
    targetId: input.targetId,
    reason: input.reason?.slice(0, 500) ?? '',
    source: input.source?.slice(0, 100) ?? 'manual',
    createdAt: Date.now(),
  };
  const client = await db();
  if (!client) {
    memBlocks.set(memKey(record.kind, record.targetId), record);
    return record;
  }
  const row = await client.blockedContent.upsert({
    where: { kind_targetId: { kind: record.kind, targetId: record.targetId } },
    create: {
      kind: record.kind,
      targetId: record.targetId,
      reason: record.reason,
      source: record.source,
    },
    update: { reason: record.reason, source: record.source },
  });
  return { ...record, createdAt: row.createdAt.getTime() };
}

export async function removeBlock(kind: BlockKind, targetId: number): Promise<boolean> {
  const client = await db();
  if (!client) return memBlocks.delete(memKey(kind, targetId));
  const result = await client.blockedContent.deleteMany({ where: { kind, targetId } });
  return result.count > 0;
}

/** 批量查黑名单（单个 kind），DB 异常时 fail-open（返回空集合，避免阅读全站不可用）。 */
export async function blockedIds(kind: BlockKind, ids: number[]): Promise<Set<number>> {
  const unique = [...new Set(ids.filter((id) => Number.isSafeInteger(id) && id > 0))];
  if (unique.length === 0) return new Set();
  const client = await db();
  if (!client) {
    const out = new Set<number>();
    for (const id of unique) if (memBlocks.has(memKey(kind, id))) out.add(id);
    return out;
  }
  try {
    const rows = await client.blockedContent.findMany({
      where: { kind, targetId: { in: unique } },
      select: { targetId: true },
    });
    return new Set(rows.map((row) => row.targetId));
  } catch (error) {
    console.warn(`[blocklist] lookup failed: ${error instanceof Error ? error.message : String(error)}`);
    return new Set();
  }
}

export async function listBlocks(limit = 200): Promise<BlockRecord[]> {
  const take = Math.min(Math.max(limit, 1), 500);
  const client = await db();
  if (!client) {
    return [...memBlocks.values()]
      .sort((a, b) => b.createdAt - a.createdAt)
      .slice(0, take);
  }
  const rows = await client.blockedContent.findMany({ orderBy: { createdAt: 'desc' }, take });
  return rows.map((row) => ({
    kind: row.kind === 'comment' ? 'comment' : 'story',
    targetId: row.targetId,
    reason: row.reason,
    source: row.source,
    createdAt: row.createdAt.getTime(),
  }));
}