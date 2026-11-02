// backend/lib/moderation.ts
//
// 内容合规审核（最小可用版）：
// - 基线：本地敏感词库（data/moderation-keywords.json，可用 MODERATION_KEYWORDS_PATH 覆盖）
// - 可选：外部内容安全服务（MODERATION_HTTP_URL），HTTP JSON 协议见 docs/ops/moderation.md
//
// 设计要点：
// - 关键词审核永远在本地跑（零成本、低延迟），HTTP 审核按需叠加；
// - 外部服务故障时的策略由 MODERATION_FAIL_MODE 控制：open=放行并告警（默认，保可用性），
//   closed=拦截并告警（翻译链路更稳妥，但服务商抖动会导致翻译不可用）；
// - 结果做短期内存缓存，避免同一段文本反复调用付费接口；
// - 日志只记录命中类别与文本 hash 前缀，不打印原文（避免把违规内容再落一遍日志）。

import { createHash } from 'node:crypto';
import { readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

export type ModerationVerdict = {
  /** 是否应拦截（不下发 / 不翻译 / 不缓存） */
  blocked: boolean;
  /** 命中类别（keyword 类别名或外部服务标签） */
  labels: string[];
  /** 内部原因（blocked 时有值） */
  reason?: string;
  provider: 'off' | 'keyword' | 'http' | 'blocklist';
};

type KeywordCategories = Record<string, string[]>;

type KeywordEntry = {
  keyword: string;
  category: string;
  /** 紧凑形式（去空格/标点），用于中文包含匹配 */
  compact: string;
  /** 含英文字母的关键词按单词边界匹配 */
  latin: RegExp | null;
};

type KeywordState = {
  path: string;
  mtimeMs: number;
  entries: KeywordEntry[];
};

const FALLBACK_CATEGORIES: KeywordCategories = {
  illegal: ['代开发票', '网络赌博', '毒品', '恐怖袭击', '色情'],
};

const VERDICT_CACHE_TTL_MS = 10 * 60 * 1000;
const VERDICT_CACHE_MAX = 2_000;
const HTTP_BATCH_SIZE = 20;

let keywordState: KeywordState | undefined;
let warnedMissingFile = false;
let warnedHttpFailure = false;

const verdictCache = new Map<string, { blocked: boolean; labels: string[]; at: number }>();

function unblocked(provider: ModerationVerdict['provider']): ModerationVerdict {
  return { blocked: false, labels: [], provider };
}

function keywordPath(): string {
  return process.env.MODERATION_KEYWORDS_PATH?.trim() || join(process.cwd(), 'data', 'moderation-keywords.json');
}

/** NFKC 归一化 + 小写 + 去零宽字符 + 空白折叠（对抗全角/零宽/多余空格绕过）。 */
function normalize(text: string): string {
  return text
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[\u200B-\u200D\uFEFF]/g, '')
    .replace(/\s+/g, ' ');
}

const COMPACT_STRIP = /[\s\-_.,，。、·:：;；!！?？'"“”‘’()（）[\]【】{}<>《》/\\|~`@#$%^&*+=]/g;

function compact(text: string): string {
  return text.replace(COMPACT_STRIP, '');
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildEntries(categories: KeywordCategories): KeywordEntry[] {
  const entries: KeywordEntry[] = [];
  for (const [category, words] of Object.entries(categories)) {
    if (!Array.isArray(words)) continue;
    for (const raw of words) {
      if (typeof raw !== 'string') continue;
      const keyword = normalize(raw).trim();
      if (!keyword) continue;
      const isLatin = /[a-z]/.test(keyword);
      entries.push({
        keyword,
        category,
        compact: compact(keyword),
        latin: isLatin ? new RegExp(`(^|[^a-z0-9])${escapeRegExp(keyword)}([^a-z0-9]|$)`) : null,
      });
    }
  }
  return entries;
}

/** 加载词库：按 mtime 缓存；文件缺失/损坏时用内置兜底词条并告警一次。 */
function loadKeywordEntries(): KeywordEntry[] {
  const path = keywordPath();
  try {
    const stat = statSync(path);
    if (keywordState && keywordState.path === path && keywordState.mtimeMs === stat.mtimeMs) {
      return keywordState.entries;
    }
    const parsed = JSON.parse(readFileSync(path, 'utf8')) as { categories?: unknown };
    const categories = parsed.categories && typeof parsed.categories === 'object' && !Array.isArray(parsed.categories)
      ? parsed.categories as KeywordCategories
      : {};
    keywordState = { path, mtimeMs: stat.mtimeMs, entries: buildEntries(categories) };
    return keywordState.entries;
  } catch (error) {
    if (!warnedMissingFile) {
      warnedMissingFile = true;
      console.warn(`[moderation] keyword file unavailable (${path}): ${error instanceof Error ? error.message : String(error)}; using fallback list`);
    }
    const fallbackPath = `fallback:${path}`;
    if (!keywordState || keywordState.path !== fallbackPath) {
      keywordState = { path: fallbackPath, mtimeMs: 0, entries: buildEntries(FALLBACK_CATEGORIES) };
    }
    return keywordState.entries;
  }
}

type ModerationMode = { keyword: boolean; http: boolean };

/**
 * MODERATION_MODE：off | keyword | http | keyword+http。
 * 未设置时默认 keyword；若同时配置了 MODERATION_HTTP_URL，则自动叠加为 keyword+http。
 */
function mode(): ModerationMode {
  const raw = process.env.MODERATION_MODE?.trim().toLowerCase();
  const hasHttpUrl = Boolean(process.env.MODERATION_HTTP_URL?.trim());
  if (raw === 'off' || raw === 'none') return { keyword: false, http: false };
  if (raw === 'http') return { keyword: false, http: hasHttpUrl };
  if (raw === 'keyword') return { keyword: true, http: false };
  if (raw === 'keyword+http' || raw === 'all') return { keyword: true, http: hasHttpUrl };
  return { keyword: true, http: hasHttpUrl };
}

export function moderationEnabled(): boolean {
  const m = mode();
  return m.keyword || m.http;
}

function failClosed(): boolean {
  return process.env.MODERATION_FAIL_MODE?.trim().toLowerCase() === 'closed';
}

function httpTimeoutMs(): number {
  const raw = Number(process.env.MODERATION_HTTP_TIMEOUT_MS);
  if (!Number.isFinite(raw) || raw <= 0) return 3_000;
  return Math.min(raw, 10_000);
}

/** 同步关键词扫描（出站过滤/单测用，不访问网络）。 */
export function scanKeywords(text: string): ModerationVerdict {
  const entries = loadKeywordEntries();
  if (!text || entries.length === 0) return unblocked(entries.length === 0 ? 'off' : 'keyword');
  const normalized = normalize(text);
  const squeezed = compact(normalized);
  const labels = new Set<string>();
  for (const entry of entries) {
    if (entry.latin) {
      if (entry.latin.test(normalized)) labels.add(entry.category);
    } else if (entry.compact.length > 0 && squeezed.includes(entry.compact)) {
      labels.add(entry.category);
    }
  }
  if (labels.size === 0) return unblocked('keyword');
  return { blocked: true, labels: [...labels], reason: 'keyword_hit', provider: 'keyword' };
}

function textHash(text: string): string {
  return createHash('sha256').update(text).digest('hex').slice(0, 16);
}

function logBlocked(verdict: ModerationVerdict, text: string): void {
  console.log(`[moderation] blocked provider=${verdict.provider} labels=${verdict.labels.join(',')} hash=${textHash(text)}`);
}

/** 供运维/测试重置词库与判定缓存（线上一般不需要）。 */
export function resetModerationCache(): void {
  keywordState = undefined;
  warnedMissingFile = false;
  warnedHttpFailure = false;
  verdictCache.clear();
}

type HttpResult = { flagged: boolean; labels: string[]; reason?: string };

function parseHttpResult(value: unknown): HttpResult {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return { flagged: false, labels: [] };
  const obj = value as Record<string, unknown>;
  const labels: string[] = [];
  if (Array.isArray(obj.labels)) {
    for (const label of obj.labels) if (typeof label === 'string' && labels.length < 20) labels.push(label);
  }
  if (typeof obj.category === 'string' && labels.length < 20) labels.push(obj.category);
  return {
    flagged: obj.flagged === true || obj.blocked === true,
    labels,
    reason: typeof obj.reason === 'string' ? obj.reason : undefined,
  };
}

function parseHttpResponse(body: unknown, expected: number): HttpResult[] {
  if (!body || typeof body !== 'object') throw new Error('moderation_invalid_response');
  const obj = body as Record<string, unknown>;
  const list = Array.isArray(obj.results) ? obj.results : Array.isArray(obj.data) ? obj.data : undefined;
  if (list && list.length === expected) return list.map(parseHttpResult);
  if (typeof obj.flagged === 'boolean' && expected === 1) return [parseHttpResult(obj)];
  throw new Error('moderation_invalid_response');
}

/** 调用外部内容安全服务（批量）。失败抛错，由 reviewTexts 按 fail 策略处理。 */
async function reviewHttpBatch(texts: string[]): Promise<HttpResult[]> {
  const url = process.env.MODERATION_HTTP_URL?.trim();
  if (!url) throw new Error('moderation_http_url_missing');
  const token = process.env.MODERATION_HTTP_TOKEN?.trim();
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const response = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify({ texts }),
    signal: AbortSignal.timeout(httpTimeoutMs()),
  });
  if (!response.ok) throw new Error(`moderation_http_${response.status}`);
  const body = await response.json() as unknown;
  return parseHttpResponse(body, texts.length);
}

function cacheKey(text: string): string {
  const m = mode();
  const signature = `${m.keyword ? 1 : 0}${m.http ? 1 : 0}:${keywordState?.mtimeMs ?? 0}:${process.env.MODERATION_HTTP_URL ?? ''}`;
  return createHash('sha256').update(`${signature}\0${text}`).digest('hex');
}

function readVerdictCache(key: string): ModerationVerdict | undefined {
  const hit = verdictCache.get(key);
  if (!hit) return undefined;
  if (Date.now() - hit.at > VERDICT_CACHE_TTL_MS) {
    verdictCache.delete(key);
    return undefined;
  }
  return { blocked: hit.blocked, labels: [...hit.labels], provider: hit.blocked ? 'http' : 'keyword' };
}

function writeVerdictCache(key: string, verdict: ModerationVerdict): void {
  if (verdictCache.size >= VERDICT_CACHE_MAX) {
    const oldest = verdictCache.keys().next().value;
    if (oldest !== undefined) verdictCache.delete(oldest);
  }
  verdictCache.set(key, { blocked: verdict.blocked, labels: [...verdict.labels], at: Date.now() });
}

/**
 * 审核一批文本（关键词 + 可选 HTTP）。
 * 返回与输入等长的判定数组；空文本视为未命中。
 */
export async function reviewTexts(texts: string[]): Promise<ModerationVerdict[]> {
  const m = mode();
  const results: ModerationVerdict[] = texts.map(() => unblocked(m.keyword || m.http ? 'keyword' : 'off'));
  if (!m.keyword && !m.http) return results;

  const candidates: number[] = [];
  for (let i = 0; i < texts.length; i += 1) {
    const text = texts[i] ?? '';
    if (text.trim().length === 0) continue;
    if (m.keyword) {
      const verdict = scanKeywords(text);
      if (verdict.blocked) {
        results[i] = verdict;
        logBlocked(verdict, text);
        continue;
      }
    }
    candidates.push(i);
  }
  if (!m.http || candidates.length === 0) return results;

  for (let start = 0; start < candidates.length; start += HTTP_BATCH_SIZE) {
    const batch = candidates.slice(start, start + HTTP_BATCH_SIZE);
    // 先吃缓存，只把未命中的送服务
    const pending: number[] = [];
    for (const index of batch) {
      const cached = readVerdictCache(cacheKey(texts[index] ?? ''));
      if (cached) results[index] = cached;
      else pending.push(index);
    }
    if (pending.length === 0) continue;
    const batchTexts = pending.map((index) => texts[index] ?? '');
    try {
      const httpResults = await reviewHttpBatch(batchTexts);
      for (let i = 0; i < pending.length; i += 1) {
        const index = pending[i];
        const raw = httpResults[i] ?? { flagged: false, labels: [] };
        const verdict: ModerationVerdict = raw.flagged
          ? { blocked: true, labels: raw.labels, reason: raw.reason ?? 'http_flagged', provider: 'http' }
          : unblocked('http');
        if (index === undefined) continue;
        results[index] = verdict;
        writeVerdictCache(cacheKey(texts[index] ?? ''), verdict);
        if (verdict.blocked) logBlocked(verdict, texts[index] ?? '');
      }
    } catch (error) {
      if (!warnedHttpFailure) {
        warnedHttpFailure = true;
        console.warn(`[moderation] http provider failed: ${error instanceof Error ? error.message : String(error)}`);
      }
      for (const index of pending) {
        if (index === undefined) continue;
        results[index] = failClosed()
          ? { blocked: true, labels: [], reason: 'moderation_unavailable', provider: 'http' }
          : unblocked('http');
      }
    }
  }
  return results;
}

/** 审核单个文本。 */
export async function reviewText(text: string): Promise<ModerationVerdict> {
  const results = await reviewTexts([text]);
  return results[0] ?? unblocked('off');
}

export type OutboundFilterMode = 'off' | 'keyword' | 'keyword+http';

/** 出站（列表/评论展示）过滤强度：默认跟随审核模式，可用 OUTBOUND_FILTER 单独调。 */
export function outboundMode(): OutboundFilterMode {
  const raw = process.env.OUTBOUND_FILTER?.trim().toLowerCase();
  if (raw === 'off' || raw === 'none') return 'off';
  if (raw === 'keyword+http' || raw === 'all' || raw === 'http') return 'keyword+http';
  if (raw === 'keyword') return 'keyword';
  const m = mode();
  if (!m.keyword && !m.http) return 'off';
  return m.http ? 'keyword+http' : 'keyword';
}

/**
 * 出站文本审核：展示链路默认只跑本地关键词（快且免费）；
 * OUTBOUND_FILTER=keyword+http 时才叠加外部服务（成本高，谨慎开启）。
 */
export async function reviewOutboundTexts(texts: string[]): Promise<ModerationVerdict[]> {
  const outbound = outboundMode();
  if (outbound === 'off') return texts.map(() => unblocked('off'));
  if (outbound === 'keyword+http') return reviewTexts(texts);
  return texts.map((text) => (text.trim().length === 0 ? unblocked('keyword') : scanKeywords(text)));
}