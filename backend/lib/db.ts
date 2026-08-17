// backend/lib/db.ts
import { PrismaClient } from '@prisma/client';

// 挂到 globalThis，防止 Next.js dev HMR 每次热重载新建 PrismaClient 耗尽连接池（Prisma 官方推荐模式）
const globalForDb = globalThis as unknown as {
  __geekreadPrisma?: Promise<PrismaClient | undefined>;
};

let client: PrismaClient | undefined;
// 模块重载（HMR）时优先复用全局已缓存的连接 Promise
let startup: Promise<PrismaClient | undefined> | undefined = globalForDb.__geekreadPrisma;

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
        // 清理孤儿 client，避免 DB 闪断反复重试时泄漏 query engine
        client?.$disconnect().catch(() => {});
        client = undefined;
        throw error;
      });
    globalForDb.__geekreadPrisma = startup;
  }
  return startup;
}
