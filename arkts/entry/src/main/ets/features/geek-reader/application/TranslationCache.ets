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
// 配额熔断闸门：非免通道（评论翻译）配额用尽后本地熔断，translate() 直接
// 拒绝 quota_exceeded，不再发起请求（省网络往返，组件秒显升级 CTA）。
// 服务端配额按 UTC 日重置（quota.ts today()），闸门按 UTC 日期存续，跨日自动失效；
// Pro 购买成功 / 列表页配额查询 remaining>0 时调用 resetQuotaGate() 主动解除。
let quotaExhaustedDay: string = ''

function utcToday(): string {
  return new Date().toISOString().slice(0, 10)
}

function quotaGateActive(): boolean {
  if (quotaExhaustedDay.length === 0) return false
  if (utcToday() !== quotaExhaustedDay) {
    quotaExhaustedDay = '' // 跨 UTC 日，服务端配额已重置
    return false
  }
  return true
}

/** 配额恢复（Pro 购买成功、列表页配额查询 remaining>0）时解除熔断。 */
export function resetQuotaGate(): void {
  quotaExhaustedDay = ''
}

function tripQuotaGate(): void {
  if (quotaGateActive()) return
  quotaExhaustedDay = utcToday()
  // 队列/窗口里未发出的非免条目直接判配额用尽；免费条目（标题/正文）不受影响
  const keptQueue: Pending[] = []
  for (let i = 0; i < queue.length; i++) {
    const it = queue[i]
    if (it.free) keptQueue.push(it)
    else it.reject(new Error('quota_exceeded'))
  }
  queue = keptQueue
  const keptIncoming: Pending[] = []
  for (let i = 0; i < incoming.length; i++) {
    const it = incoming[i]
    if (it.free) keptIncoming.push(it)
    else it.reject(new Error('quota_exceeded'))
  }
  incoming = keptIncoming
}

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
    // 配额熔断：remaining=0 或任一条目 quota_exceeded 即触发（仅非免响应携带）
    if (res.remainingTranslations === 0) tripQuotaGate()
    for (let i = 0; i < chunk.length; i++) {
      const r = res.results[i]
      if (r !== undefined && r.translation !== undefined && r.translation.length > 0) {
        cache.set(cacheKey(lang, chunk[i].text), r.translation)
        chunk[i].resolve(r.translation)
      } else {
        if (r?.error === 'quota_exceeded') tripQuotaGate()
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
  // 空文本（链接/图片型评论 HTML 清洗后为空）：无物可译，直接返回空串，
  // 不进队列不发请求（曾污染整批触发服务端 400）。
  if (text.trim().length === 0) return Promise.resolve('')
  // 配额熔断：非免翻译直接拒绝，不发请求；组件 catch 到 quota_exceeded 显示升级 CTA。
  // 免费通道（标题/正文/精华评论）不扣配额，不受闸门影响。
  if (!free && quotaGateActive()) {
    return Promise.reject(new Error('quota_exceeded'))
  }
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
