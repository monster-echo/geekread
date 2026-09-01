// backend/lib/quota-store.ts
import { db } from './db';

export type Reservation = {
  allowed: boolean;
  remaining: number;
  rollback: () => Promise<void>;
};

// ---- 内存回退（dev/test）----
const memUsage = new Map<string, number>();

export async function reserveTranslation(
  day: string,
  clientId: string,
  limit: number,
): Promise<Reservation> {
  const key = `${day}:${clientId}`;
  const client = await db();
  if (!client) {
    const used = memUsage.get(key) ?? 0;
    if (used >= limit) return { allowed: false, remaining: 0, rollback: async () => undefined };
    memUsage.set(key, used + 1);
    return {
      allowed: true,
      remaining: limit - used - 1,
      rollback: async () => {
        const current = memUsage.get(key) ?? 1;
        if (current <= 1) memUsage.delete(key);
        else memUsage.set(key, current - 1);
      },
    };
  }

  // upsert 原子自增；超出上限立即回减并拒绝（并发安全：单行 UPDATE 原子）
  const row = await client.quotaUsage.upsert({
    where: { day_clientId: { day, clientId } },
    create: { day, clientId, used: 1 },
    update: { used: { increment: 1 } },
  });
  if (row.used > limit) {
    await client.quotaUsage.update({
      where: { day_clientId: { day, clientId } },
      data: { used: { decrement: 1 } },
    }).catch((error) => {
      process.stderr.write(`[geekread][quota] rollback-over-limit failed: ${String(error)}\n`);
    });
    return { allowed: false, remaining: 0, rollback: async () => undefined };
  }
  return {
    allowed: true,
    remaining: Math.max(0, limit - row.used),
    rollback: async () => {
      await client.quotaUsage
        .update({
          where: { day_clientId: { day, clientId } },
          data: { used: { decrement: 1 } },
        })
        .catch(() => undefined);
    },
  };
}

export async function peekTranslation(day: string, clientId: string): Promise<number> {
  const client = await db();
  if (!client) return memUsage.get(`${day}:${clientId}`) ?? 0;
  const row = await client.quotaUsage.findUnique({
    where: { day_clientId: { day, clientId } },
  });
  return row?.used ?? 0;
}

export type TopicReservation = {
  allowed: boolean;
  remainingTopics: number;
  /// 本次是否新解锁了一篇 topic（消耗了 1 个 topic 配额）
  charged: boolean;
};

// ---- topic 配额的 in-memory 回退（dev/test）----
const memTopics = new Map<string, number>(); // `${day}:${clientId}` -> used topics
const memTopicRequests = new Map<string, number>(); // `${day}:${clientId}:${storyId}` -> request 批数

/**
 * 按 topic 计配额：同一 storyId 当天首次翻译请求解锁该 topic（+1 topic），
 * 之后同 topic 的请求不再重复计数，只计入该 topic 的批数上限 requestCap。
 * 并发安全：PG 用 FOR UPDATE 锁当日使用行串行化"解锁裁决"；
 * 无 DB 时内存单线程无竞态。
 */
export async function reserveTopicTranslation(
  day: string,
  clientId: string,
  storyId: number,
  topicLimit: number,
  requestCap: number,
): Promise<TopicReservation> {
  const client = await db();
  if (!client) {
    const usedKey = `${day}:${clientId}`;
    const reqKey = `${day}:${clientId}:${storyId}`;
    const used = memTopics.get(usedKey) ?? 0;
    const reqs = memTopicRequests.get(reqKey) ?? 0;
    const opened = reqs === 0;
    if (opened && used >= topicLimit) {
      return { allowed: false, remainingTopics: 0, charged: false };
    }
    memTopicRequests.set(reqKey, reqs + 1);
    const nextReqs = reqs + 1;
    if (opened) memTopics.set(usedKey, used + 1);
    const remaining = Math.max(0, topicLimit - (opened ? used + 1 : used));
    if (nextReqs > requestCap) {
      return { allowed: false, remainingTopics: remaining, charged: opened };
    }
    return { allowed: true, remainingTopics: remaining, charged: opened };
  }

  return client.$transaction(async (tx) => {
    // 锁当日使用行，串行化"这篇 topic 是否新解锁"的裁决
    const rows = await tx.$queryRaw<{ used: number }[]>`
      SELECT "used" FROM "QuotaUsage" WHERE "day" = ${day} AND "clientId" = ${clientId} FOR UPDATE`;
    const row = rows[0];
    const used = row ? row.used : 0;

    const prev = await tx.topicUsage.findUnique({
      where: { day_clientId_storyId: { day, clientId, storyId } },
    });
    const opened = prev === null;
    if (opened && used >= topicLimit) {
      return { allowed: false, remainingTopics: 0, charged: false };
    }

    if (opened) {
      await tx.quotaUsage.upsert({
        where: { day_clientId: { day, clientId } },
        create: { day, clientId, used: 1 },
        update: { used: { increment: 1 } },
      });
    }
    const reqRow = await tx.topicUsage.upsert({
      where: { day_clientId_storyId: { day, clientId, storyId } },
      create: { day, clientId, storyId, requests: 1 },
      update: { requests: { increment: 1 } },
    });
    const remaining = Math.max(0, topicLimit - used - (opened ? 1 : 0));
    if (reqRow.requests > requestCap) {
      return { allowed: false, remainingTopics: remaining, charged: opened };
    }
    return { allowed: true, remainingTopics: remaining, charged: opened };
  });
}
