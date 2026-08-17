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
// 全局同时在途的 /api/translate 请求数上限。分屏渲染下滚动会连续触发新批次
// （每 10 条评论一个请求），无上限时 N 批并行 × 服务端 8 worker 会打爆上游
// 触发限流/超时。2 在途 ≈ 服务端 16 个 LLM 并发，与上游承受力匹配。
const MAX_INFLIGHT: number = 2

const cache: Map<string, string> = new Map<string, string>()
const inFlight: Map<string, Promise<string>> = new Map<string, Promise<string>>()
// 本窗口新到的条目（50ms 收集期，凑批用），窗口到期后整体插到队列头
let incoming: Pending[] = []
// 待分发队列（未发出 HTTP）。新批次插队到头部：用户当前视口优先翻译；
// 单次分发从头取 ≤MAX_ENTRIES 条（新在前、旧在后），旧条目不会被饿死。
let queue: Pending[] = []
let inflightRequests: number = 0
let timer: number = -1

function cacheKey(lang: TargetLanguage, text: string): string {
  return `${lang}\n${text}`
}

function scheduleFlush(): void {
  if (timer !== -1) return
  timer = setTimeout(() => { timer = -1; flush() }, WINDOW_MS)
}

/** 从队列头取一组同 lang+free、条数/字符数不超限的条目（保持原相对顺序）。 */
function takeChunk(): Pending[] {
  const head = queue[0]
  if (head === undefined) return []
  const chunk: Pending[] = []
  const rest: Pending[] = []
  let chars: number = 0
  for (let i = 0; i < queue.length; i++) {
    const it = queue[i]
    if (it.lang !== head.lang || it.free !== head.free ||
      chunk.length >= MAX_ENTRIES || chars + it.text.length > MAX_TOTAL_CHARS) {
      rest.push(it)
      continue
    }
    chunk.push(it)
    chars += it.text.length
  }
  queue = rest
  return chunk
}

/** 分发一个 chunk 到后端（内部消化所有异常，不会 reject）。 */
async function dispatchChunk(chunk: Pending[]): Promise<void> {
  const lang = chunk[0].lang
  const entries: TranslateEntry[] = []
  for (let i = 0; i < chunk.length; i++) {
    entries.push({ key: String(i), text: chunk[i].text })
  }
  const req: TranslateRequest = { targetLanguage: lang, entries, free: chunk[0].free === true }
  try {
    const res: TranslateResponse = await translateBatch(req)
    for (let i = 0; i < chunk.length; i++) {
      const r = res.results[i]
      if (r !== undefined && r.translation !== undefined && r.translation.length > 0) {
        cache.set(cacheKey(lang, chunk[i].text), r.translation)
        chunk[i].resolve(r.translation)
      } else {
        chunk[i].reject(new Error(r?.error ?? 'translation_failed'))
      }
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'translation_failed'
    for (let i = 0; i < chunk.length; i++) {
      chunk[i].reject(new Error(msg))
    }
  }
}

/** 调度循环：在途请求低于上限且队列非空时持续取 chunk 发出。 */
function pump(): void {
  while (inflightRequests < MAX_INFLIGHT && queue.length > 0) {
    const chunk = takeChunk()
    if (chunk.length === 0) return
    inflightRequests++
    // dispatchChunk 不抛异常（内部全捕获），完成一个补一个
    dispatchChunk(chunk).then(() => {
      inflightRequests--
      pump()
    })
  }
}

/** 窗口到期：本窗口新挂载的条目（用户当前视口）插到队列头，优先分发。 */
function flush(): void {
  if (incoming.length === 0) return
  const merged: Pending[] = incoming
  for (let i = 0; i < queue.length; i++) merged.push(queue[i])
  queue = merged
  incoming = []
  pump()
}

export function translate(text: string, lang: TargetLanguage, free: boolean = false): Promise<string> {
  const k = cacheKey(lang, text)
  const hit = cache.get(k)
  if (hit !== undefined) return Promise.resolve(hit)
  const flying = inFlight.get(k)
  if (flying !== undefined) return flying
  const p = new Promise<string>((resolve, reject) => {
    incoming.push({ text, lang, free, resolve, reject })
    scheduleFlush()
  })
  inFlight.set(k, p)
  p.then(() => { inFlight.delete(k) }).catch(() => { inFlight.delete(k) })
  return p
}
