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
