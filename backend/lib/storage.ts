import { createHash } from 'node:crypto';
import { createClient, RedisClientType } from 'redis';

type Reservation = {
  allowed: boolean;
  remaining: number;
  rollback: () => Promise<void>;
};

const localUsage = new Map<string, number>();
const localTranslationCache = new Map<string, string>();
const localJsonCache = new Map<string, { freshUntil: number; expiresAt: number; value: unknown }>();
const reservationLocks = new Map<string, Promise<void>>();
let redisClient: RedisClientType | undefined;
let redisStartup: Promise<RedisClientType> | undefined;

function production(): boolean {
  return process.env.NODE_ENV === 'production';
}

async function redis(): Promise<RedisClientType | undefined> {
  const url = process.env.REDIS_URL?.trim();
  if (!url) {
    if (production()) throw new Error('redis_not_configured');
    return undefined;
  }
  if (!redisStartup) {
    redisClient = createClient({
      url,
      disableOfflineQueue: true,
      socket: {
        connectTimeout: 4_000,
        reconnectStrategy: false,
      },
    });
    redisClient.on('error', (error) => process.stderr.write(`redis: ${String(error)}\n`));
    redisStartup = redisClient.connect().then(() => redisClient!);
  }
  return redisStartup;
}

function translationCacheKey(text: string, targetLanguage: string): string {
  const version = process.env.TRANSLATION_CACHE_VERSION?.trim() || 'v1';
  const model = process.env.MODEL_NAME?.trim() || 'unknown-model';
  const digest = createHash('sha256')
    .update(version)
    .update('\0')
    .update(model)
    .update('\0')
    .update(targetLanguage)
    .update('\0')
    .update(text)
    .digest('hex');
  return `geekread:translation-cache:${digest}`;
}

async function withReservationLock<T>(key: string, operation: () => Promise<T>): Promise<T> {
  const previous = reservationLocks.get(key) ?? Promise.resolve();
  let release!: () => void;
  const current = new Promise<void>((resolve) => {
    release = resolve;
  });
  const queued = previous.then(() => current);
  reservationLocks.set(key, queued);

  await previous;
  try {
    return await operation();
  } finally {
    release();
    if (reservationLocks.get(key) === queued) reservationLocks.delete(key);
  }
}

export async function getCachedTranslation(
  text: string,
  targetLanguage: string,
): Promise<string | undefined> {
  const key = translationCacheKey(text, targetLanguage);
  const client = await redis();
  const value = client ? await client.get(key) : localTranslationCache.get(key);
  return value?.trim() || undefined;
}

export async function cacheTranslation(
  text: string,
  targetLanguage: string,
  translation: string,
): Promise<void> {
  const key = translationCacheKey(text, targetLanguage);
  const value = translation.trim();
  if (!value) return;
  const client = await redis();
  if (!client) {
    localTranslationCache.set(key, value);
    return;
  }
  const ttlSeconds = Number(process.env.TRANSLATION_CACHE_TTL_SECONDS ?? 2_592_000);
  await client.set(key, value, { EX: ttlSeconds });
}

export async function getJsonCache<T>(
  key: string,
): Promise<{ value: T; stale: boolean } | undefined> {
  const client = await redis();
  let entry: { freshUntil: number; value: T } | undefined;
  if (client) {
    const encoded = await client.get(`geekread:data-cache:${key}`);
    if (!encoded) return undefined;
    try {
      entry = JSON.parse(encoded) as { freshUntil: number; value: T };
    } catch {
      await client.del(`geekread:data-cache:${key}`);
      return undefined;
    }
  } else {
    const local = localJsonCache.get(key);
    if (!local) return undefined;
    if (local.expiresAt <= Date.now()) {
      localJsonCache.delete(key);
      return undefined;
    }
    entry = { freshUntil: local.freshUntil, value: local.value as T };
  }
  return { value: entry.value, stale: entry.freshUntil <= Date.now() };
}

export async function setJsonCache<T>(
  key: string,
  value: T,
  freshTtlSeconds: number,
  staleTtlSeconds: number,
): Promise<void> {
  const now = Date.now();
  const entry = { freshUntil: now + freshTtlSeconds * 1000, value };
  const client = await redis();
  if (client) {
    await client.set(`geekread:data-cache:${key}`, JSON.stringify(entry), {
      EX: staleTtlSeconds,
    });
    return;
  }
  localJsonCache.set(key, {
    ...entry,
    expiresAt: now + staleTtlSeconds * 1000,
  });
}

export async function reserveTranslation(
  day: string,
  clientId: string,
  limit: number,
): Promise<Reservation> {
  const key = `geekread:translation:${day}:${clientId}`;
  const client = await redis();
  if (!client) {
    const used = localUsage.get(key) ?? 0;
    if (used >= limit) return { allowed: false, remaining: 0, rollback: async () => undefined };
    localUsage.set(key, used + 1);
    return {
      allowed: true,
      remaining: limit - used - 1,
      rollback: async () => {
        const current = localUsage.get(key) ?? 1;
        if (current <= 1) localUsage.delete(key);
        else localUsage.set(key, current - 1);
      },
    };
  }

  return withReservationLock(key, async () => {
    const used = Number(await client.get(key) ?? 0);
    if (used >= limit) {
      return { allowed: false, remaining: 0, rollback: async () => undefined };
    }

    const next = used + 1;
    await client.set(key, String(next), { EX: 172800 });
    return {
      allowed: true,
      remaining: Math.max(0, limit - next),
      rollback: async () => withReservationLock(key, async () => {
        const current = Number(await client.get(key) ?? 0);
        if (current <= 1) await client.del(key);
        else await client.set(key, String(current - 1), { EX: 172800 });
        return undefined;
      }),
    };
  });
}

export async function peekTranslation(day: string, clientId: string): Promise<number> {
  const key = `geekread:translation:${day}:${clientId}`;
  const client = await redis();
  if (!client) return localUsage.get(key) ?? 0;
  return Number(await client.get(key) ?? 0);
}

export function storageConfiguration(): { redis: boolean } {
  return { redis: Boolean(process.env.REDIS_URL?.trim()) };
}
