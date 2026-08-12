import { TargetLanguage } from '../domain/Models'
import { translateBatch, TranslateRequest, TranslateResponse, TranslateEntry } from '../data/GeekReaderApiClient'

interface Pending {
  text: string
  lang: TargetLanguage
  free: boolean
  resolve: (t: string) => void
  reject: (e: Error) => void
}

const WINDOW_MS: number = 50
const MAX_ENTRIES: number = 20
const MAX_TOTAL_CHARS: number = 12000

const cache: Map<string, string> = new Map<string, string>()
const inFlight: Map<string, Promise<string>> = new Map<string, Promise<string>>()
let pending: Pending[] = []
let timer: number = -1

function cacheKey(lang: TargetLanguage, text: string): string {
  return `${lang}\n${text}`
}

function scheduleFlush(): void {
  if (timer !== -1) return
  timer = setTimeout(() => { timer = -1; flush() }, WINDOW_MS)
}

function chunkEntries(items: Pending[], maxEntries: number, maxChars: number): Pending[][] {
  const chunks: Pending[][] = []
  let cur: Pending[] = []
  let chars: number = 0
  for (let i = 0; i < items.length; i++) {
    const it = items[i]
    if (cur.length >= maxEntries || chars + it.text.length > maxChars) {
      if (cur.length > 0) chunks.push(cur)
      cur = []
      chars = 0
    }
    cur.push(it)
    chars += it.text.length
  }
  if (cur.length > 0) chunks.push(cur)
  return chunks
}

async function flush(): Promise<void> {
  const batch: Pending[] = pending
  pending = []
  if (batch.length === 0) return
  let lang: TargetLanguage = batch[0].lang
  if (!lang) lang = 'zh-Hans' // 兜底：lang 丢失时用简体中文
  for (let start = 0; start < batch.length; start += MAX_ENTRIES) {
    const end: number = Math.min(start + MAX_ENTRIES, batch.length)
    const entries: TranslateEntry[] = []
    for (let i = start; i < end; i++) {
      entries.push({ key: String(i - start), text: batch[i].text })
    }
    const req: TranslateRequest = { targetLanguage: lang, entries, free: batch[0].free === true }
    try {
      const res: TranslateResponse = await translateBatch(req)
      for (let pi = 0; pi < entries.length; pi++) {
        const p = batch[start + pi]
        const r = res.results[pi]
        if (r !== undefined && r.translation !== undefined && r.translation.length > 0) {
          cache.set(cacheKey(lang, p.text), r.translation)
          p.resolve(r.translation)
        } else {
          p.reject(new Error(r?.error ?? 'translation_failed'))
        }
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'translation_failed'
      for (let pi = 0; pi < entries.length; pi++) {
        batch[start + pi].reject(new Error(msg))
      }
    }
  }
}

export function translate(text: string, lang: TargetLanguage, free: boolean = false): Promise<string> {
  const k = cacheKey(lang, text)
  const hit = cache.get(k)
  if (hit !== undefined) return Promise.resolve(hit)
  const flying = inFlight.get(k)
  if (flying !== undefined) return flying
  const p = new Promise<string>((resolve, reject) => {
    pending.push({ text, lang, free, resolve, reject })
    scheduleFlush()
  })
  inFlight.set(k, p)
  p.then(() => { inFlight.delete(k) }).catch(() => { inFlight.delete(k) })
  return p
}
