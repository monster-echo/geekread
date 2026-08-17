import { createHash } from 'node:crypto';
import { db } from './db';

// ---- 内存回退（dev/test）----
const memTranslations = new Map<string, string>();
const memSummaries = new Map<string, string>();

function digest(parts: string[]): string {
  const hash = createHash('sha256');
  for (const part of parts) hash.update(part).update('\0');
  return hash.digest('hex');
}

function translationKey(text: string, targetLanguage: string): string {
  const version = process.env.TRANSLATION_CACHE_VERSION?.trim() || 'v1';
  const model = process.env.MODEL_NAME?.trim() || 'unknown-model';
  return digest([version, model, targetLanguage, text]);
}

function summaryKey(storyId: number, targetLanguage: string): string {
  const version = process.env.TRANSLATION_CACHE_VERSION?.trim() || 'v1';
  const model = process.env.MODEL_NAME?.trim() || 'unknown-model';
  return digest([version, model, targetLanguage, String(storyId)]);
}

export async function getCachedTranslation(
  text: string,
  targetLanguage: string,
): Promise<string | undefined> {
  const hash = translationKey(text, targetLanguage);
  const client = await db();
  if (!client) return memTranslations.get(hash);
  const row = await client.translation.findUnique({ where: { hash } });
  return row?.result.trim() || undefined;
}

export async function cacheTranslation(
  text: string,
  targetLanguage: string,
  translation: string,
): Promise<void> {
  const value = translation.trim();
  if (!value) return;
  const hash = translationKey(text, targetLanguage);
  const client = await db();
  if (!client) {
    memTranslations.set(hash, value);
    return;
  }
  // 永久保存：同 hash 只写一次，冲突时保留旧值即可（幂等）
  await client.translation.upsert({
    where: { hash },
    create: { hash, lang: targetLanguage, source: text, result: value },
    update: { result: value },
  });
}

export async function getCachedSummary(
  storyId: number,
  targetLanguage: string,
): Promise<string | undefined> {
  const hash = summaryKey(storyId, targetLanguage);
  const client = await db();
  if (!client) return memSummaries.get(hash);
  const row = await client.summary.findUnique({ where: { hash } });
  return row?.result.trim() || undefined;
}

export async function cacheSummary(
  storyId: number,
  targetLanguage: string,
  summary: string,
): Promise<void> {
  const value = summary.trim();
  if (!value) return;
  const hash = summaryKey(storyId, targetLanguage);
  const client = await db();
  if (!client) {
    memSummaries.set(hash, value);
    return;
  }
  await client.summary.upsert({
    where: { hash },
    create: { hash, storyId, lang: targetLanguage, result: value },
    update: { result: value },
  });
}
