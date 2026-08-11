import type { TargetLanguage } from '../domain/models';
import { translateBatch, type TranslateRequest, type TranslateResponse } from '../data/GeekReaderApiClient';

type Pending = {
  text: string;
  lang: TargetLanguage;
  resolve: (t: string) => void;
  reject: (e: unknown) => void;
};

const WINDOW_MS = 50;
const MAX_ENTRIES = 20;
const MAX_TOTAL_CHARS = 12_000;

const cache = new Map<string, string>();
const inFlight = new Map<string, Promise<string>>();
let pending: Pending[] = [];
let timer: ReturnType<typeof setTimeout> | null = null;
let transport: (req: TranslateRequest) => Promise<TranslateResponse> = translateBatch;

export function setTranslationTransport(t: (req: TranslateRequest) => Promise<TranslateResponse>) {
  transport = t;
}

export function clearTranslationCache() {
  cache.clear();
  inFlight.clear();
  pending = [];
  if (timer) { clearTimeout(timer); timer = null; }
}

function cacheKey(lang: TargetLanguage, text: string) {
  return `${lang}\n${text}`;
}

function scheduleFlush() {
  if (timer) return;
  timer = setTimeout(() => { timer = null; void flush(); }, WINDOW_MS);
}

function chunkEntries(items: Pending[], maxEntries: number, maxChars: number): Pending[][] {
  const chunks: Pending[][] = [];
  let cur: Pending[] = [];
  let chars = 0;
  for (const it of items) {
    if (cur.length >= maxEntries || chars + it.text.length > maxChars) {
      if (cur.length) chunks.push(cur);
      cur = []; chars = 0;
    }
    cur.push(it); chars += it.text.length;
  }
  if (cur.length) chunks.push(cur);
  return chunks;
}

async function flush() {
  const batch = pending;
  pending = [];
  if (batch.length === 0) return;
  const byLang = new Map<TargetLanguage, Pending[]>();
  for (const p of batch) {
    const arr = byLang.get(p.lang) ?? [];
    arr.push(p);
    byLang.set(p.lang, arr);
  }
  for (const [lang, items] of byLang) {
    for (const chunk of chunkEntries(items, MAX_ENTRIES, MAX_TOTAL_CHARS)) {
      try {
        const res = await transport({
          targetLanguage: lang,
          entries: chunk.map((p, i) => ({ key: String(i), text: p.text })),
        });
        const byText = new Map(chunk.map((p, i) => [String(i), { p, r: res.results[i] }]));
        for (const { p, r } of byText.values()) {
          if (r?.translation) { cache.set(cacheKey(lang, p.text), r.translation); p.resolve(r.translation); }
          else p.reject(new Error(r?.error ?? 'translation_failed'));
        }
      } catch (e) {
        for (const p of chunk) p.reject(e);
      }
    }
  }
}

export function translate(text: string, lang: TargetLanguage): Promise<string> {
  const k = cacheKey(lang, text);
  const hit = cache.get(k);
  if (hit) return Promise.resolve(hit);
  const flying = inFlight.get(k);
  if (flying) return flying;
  const p = new Promise<string>((resolve, reject) => {
    pending.push({ text, lang, resolve, reject });
    scheduleFlush();
  });
  inFlight.set(k, p);
  p.finally(() => inFlight.delete(k));
  return p;
}
