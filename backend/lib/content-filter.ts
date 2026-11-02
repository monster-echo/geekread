// backend/lib/content-filter.ts
//
// 出站内容过滤：黑名单（人工/举报处置）+ 本地关键词审核（可选叠加外部审核服务）。
// 只作用于"下发给客户端"的这一层，不改动 hnItem 原始缓存，便于误判时快速解封。

import { blockedIds, type BlockKind } from './blocklist';
import { reviewOutboundTexts } from './moderation';

export type HnItemLike = Record<string, unknown>;

export function itemKind(item: HnItemLike | null | undefined, fallback: BlockKind): BlockKind {
  const type = item?.type;
  if (type === 'comment') return 'comment';
  if (type === 'story' || type === 'job' || type === 'poll') return 'story';
  return fallback;
}

/** 参与审核的可见文本：标题 + 正文（评论只有 text）。 */
export function itemText(item: HnItemLike): string {
  const parts: string[] = [];
  if (typeof item.title === 'string' && item.title.length > 0) parts.push(item.title);
  if (typeof item.text === 'string' && item.text.length > 0) parts.push(item.text);
  return parts.join('\n');
}

/** 单篇 story 是否被人工拉黑（translate/summarize 入口用）。 */
export async function isStoryBlocked(storyId: number): Promise<boolean> {
  const blocked = await blockedIds('story', [storyId]);
  return blocked.has(storyId);
}

/**
 * 计算一批 HN item 中需要下架的 id：
 * 1) 黑名单命中（story/comment 分开查）；
 * 2) 出站审核（默认只跑本地关键词；OUTBOUND_FILTER=keyword+http 时叠加外部服务）。
 */
export async function blockedIdsForItems(
  items: Array<HnItemLike | null | undefined>,
  fallback: BlockKind,
): Promise<Set<number>> {
  const grouped: Record<BlockKind, number[]> = { story: [], comment: [] };
  for (const item of items) {
    if (!item) continue;
    const id = Number(item.id);
    if (!Number.isSafeInteger(id) || id <= 0) continue;
    grouped[itemKind(item, fallback)].push(id);
  }

  const blocked = new Set<number>();
  for (const kind of ['story', 'comment'] as const) {
    if (grouped[kind].length === 0) continue;
    const hits = await blockedIds(kind, grouped[kind]);
    for (const id of hits) blocked.add(id);
  }

  const candidates = items.filter((item): item is HnItemLike => {
    if (!item) return false;
    const id = Number(item.id);
    return Number.isSafeInteger(id) && id > 0 && !blocked.has(id);
  });
  if (candidates.length === 0) return blocked;

  const verdicts = await reviewOutboundTexts(candidates.map(itemText));
  for (let i = 0; i < candidates.length; i += 1) {
    const item = candidates[i];
    if (!item) continue;
    if (verdicts[i]?.blocked) blocked.add(Number(item.id));
  }
  return blocked;
}