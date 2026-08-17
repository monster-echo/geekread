// backend/lib/db.ts
import { PrismaClient } from '@prisma/client';

let client: PrismaClient | undefined;
let startup: Promise<PrismaClient | undefined> | undefined;

function production(): boolean {
  return process.env.NODE_ENV === 'production';
}

/**
 * Prisma 单例。语义对齐旧 lib/storage.ts 的 redis()：
 * - 生产缺 DATABASE_URL → throw pg_not_configured（fail fast）
 * - dev/test 无 DATABASE_URL → undefined，调用方走内存回退（vitest 不连库）
 */
export async function db(): Promise<PrismaClient | undefined> {
  const url = process.env.DATABASE_URL?.trim();
  if (!url) {
    if (production()) throw new Error('pg_not_configured');
    return undefined;
  }
  if (!startup) {
    client = new PrismaClient({ log: ['error', 'warn'] });
    startup = client
      .$connect()
      .then(() => client)
      .catch((error) => {
        startup = undefined; // 失败不缓存，下次重连
        throw error;
      });
  }
  return startup;
}
