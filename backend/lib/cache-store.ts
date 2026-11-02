import { createHash } from 'node:crypto';
import { db } from './db';

// ---- 内存回退（dev/test）----
// 存 source/lang 便于违规内容下架时按原文清理（与 PG translation.source 对齐）
type MemTranslation = { source: string; lang: string; result: string };
type MemSummary = { storyId: number; result: string };
const memTranslations = new Map<string, MemTranslation>();
const memSummaries = new Map<string, MemSummary>();

function digest(parts: string[]): string {
  return createHash('sha256').update(parts.join('\0')).digest('hex');
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
  if (!client) return memTranslations.get(hash)?.result;
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
    memTranslations.set(hash, { source: text, lang: targetLanguage, result: value });
    return;
  }
  // 永久保存：幂等 upsert，同 hash 重写 result（模型升级重译时刷新）
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
  if (!client) return memSummaries.get(hash)?.result;
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
    memSummaries.set(hash, { storyId, result: value });
    return;
  }
  await client.summary.upsert({
    where: { hash },
    create: { hash, storyId, lang: targetLanguage, result: value },
    update: { result: value },
  });
}

/**
 * 按原文批量清理翻译缓存（违规内容下架时调用）。
 * 返回删除行数；空输入直接跳过。
 */
export async function purgeTranslationsBySource(sources: string[]): Promise<number> {
  const unique = [...new Set(sources.map((source) => source.trim()).filter((source) => source.length > 0))];
  if (unique.length === 0) return 0;
  const client = await db();
  if (!client) {
    const wanted = new Set(unique);
    let removed = 0;
    for (const [hash, row] of memTranslations) {
      if (wanted.has(row.source)) {
        memTranslations.delete(hash);
        removed += 1;
      }
    }
    return removed;
  }
  const result = await client.translation.deleteMany({ where: { source: { in: unique } } });
  return result.count;
}

/** 删除某篇 story 的 AI 摘要缓存（story 被下架时调用）。 */
export async function purgeSummariesByStory(storyId: number): Promise<number> {
  const client = await db();
  if (!client) {
    let removed = 0;
    for (const [hash, row] of memSummaries) {
      if (row.storyId === storyId) {
        memSummaries.delete(hash);
        removed += 1;
      }
    }
    return removed;
  }
  const result = await client.summary.deleteMany({ where: { storyId } });
  return result.count;
}