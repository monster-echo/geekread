import http from '@ohos.net.http'
import { localStore } from '../../../data/LocalStore'
import { HNItem, Story, TargetLanguage } from '../domain/Models'
import { toStory } from '../domain/Models'
import { getEntitlementToken } from './Entitlement'
import { telemetry } from '../../../telemetry/Telemetry'

const GEEK_READER_BASE: string = 'https://geekread.zhongbei.tech'

/** BusinessError（http 请求失败）的最小结构，用于提取真实报错。 */
interface HttpErrorLike {
  message?: string
  code?: number
}

/** 后端 errorResponse 的响应体结构（{ error: "invalid_request" } 等）。 */
interface ApiErrorBody {
  error?: string
}

export interface TranslateEntry {
  key: string
  text: string
}

export interface TranslateRequest {
  targetLanguage: TargetLanguage
  entries: TranslateEntry[]
  free?: boolean
  /** 评论翻译的所属 topic（story）。带上后服务端按 topic 计配额：同篇只扣 1 次 */
  topicId?: number
}

export interface TranslateResult {
  key: string
  translation?: string
  cached?: boolean
  error?: string
}

export interface TranslateResponse {
  results: TranslateResult[]
  /** topic 计费（带 storyId 的请求）返回剩余可翻译话题数 */
  remainingTopics?: number
  /** legacy 按条计费（无 storyId）返回剩余可翻译条数 */
  remainingTranslations?: number
}

export interface ItemsResponse {
  items: (HNItem | null)[]
  cached: boolean
  stale: boolean
}

async function authHeaders(): Promise<Record<string, string>> {
  const headers: Record<string, string> = { 'content-type': 'application/json' }
  const installId = localStore.installationId()
  if (installId.length > 0) headers['x-install-id'] = installId
  const token = await getEntitlementToken()
  if (token.length > 0) headers['authorization'] = `Bearer ${token}`
  return headers
}

async function send(path: string, method: http.RequestMethod, body?: string): Promise<string> {
  const client = http.createHttp()
  try {
    const response = await client.request(`${GEEK_READER_BASE}${path}`, {
      method,
      header: await authHeaders(),
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 8000,
      // 翻译/摘要大批次（20条/批 ÷ 后端并发）冷缓存可达 ~19s，15s 会误杀
      readTimeout: 30000,
    })
    const text = String(response.result)
    if (response.responseCode < 200 || response.responseCode >= 300) {
      // 后端 errorResponse 返回 { error: "invalid_request" } 等具体原因，
      // 解析后拼进错误消息，避免 UI 只显示笼统的 geekreader_400。
      let detail = ''
      try {
        const parsed = JSON.parse(text) as ApiErrorBody
        if (parsed?.error !== undefined && parsed.error.length > 0) detail = parsed.error
      } catch {
        // 响应体非 JSON（网关/代理错误页），无详情可提取
      }
      console.error(`[geekread][reader] ${path} HTTP ${response.responseCode}${detail.length > 0 ? ' ' + detail : ''}`)
      throw new Error(`geekreader_${response.responseCode}${detail.length > 0 ? ': ' + detail : ''}`)
    }
    return text
  } catch (e) {
    // http.createHttp 失败抛的是 BusinessError 对象（非 Error 实例），String() 会变成
    // "[object Object]" 丢失真实原因；这里统一提取 message/code。
    let msg = String(e)
    if (e instanceof Error) {
      if (e.message.length > 0) msg = e.message
    } else {
      const like = e as HttpErrorLike
      if (like.message !== undefined && like.message.length > 0) msg = like.message
      else if (like.code !== undefined) msg = String(like.code)
    }
    console.error(`[geekread][reader] ${path} failed: ${msg}`)
    telemetry.report(new Error(`reader_network_${path.replace(/\//g, '_')}: ${msg}`))
    throw new Error(`geekreader_network: ${msg}`)
  } finally {
    client.destroy()
  }
}

/** 首页列表：一次请求返回完整 story（后端已合并列表+条目），映射为 Story[]。 */
export async function fetchStories(type: string): Promise<Story[]> {
  const text = await send(`/api/reader/stories?type=${type}`, http.RequestMethod.GET)
  const res = JSON.parse(text) as ItemsResponse
  const out: Story[] = []
  for (let i = 0; i < res.items.length; i++) {
    const s = toStory(res.items[i])
    if (s !== null) out.push(s)
  }
  return out
}

export async function fetchItems(ids: number[]): Promise<ItemsResponse> {
  const text = await send(`/api/reader/items`, http.RequestMethod.POST, JSON.stringify({ ids }))
  return JSON.parse(text) as ItemsResponse
}

/** 服务端一次解析整棵评论树（并发拉取，避免前端逐层往返）。 */
export async function fetchStoryTree(storyId: number): Promise<ItemsResponse> {
  const text = await send(`/api/reader/tree`, http.RequestMethod.POST, JSON.stringify({ storyId }))
  return JSON.parse(text) as ItemsResponse
}

/** 内容举报（评论违规反馈）。 */
export async function reportComment(storyId: number, commentId: number, reason: string, text?: string): Promise<void> {
  await send(`/api/reader/report`, http.RequestMethod.POST, JSON.stringify({ storyId, commentId, reason, text }))
}

export async function translateBatch(req: TranslateRequest): Promise<TranslateResponse> {
  const text = await send(`/api/translate`, http.RequestMethod.POST, JSON.stringify(req))
  return JSON.parse(text) as TranslateResponse
}

export interface SummarizeRequest {
  storyId: number
  title: string
  text?: string
  comments: string[]
  targetLanguage: TargetLanguage
}

export interface SummarizeResponse {
  summary: string
  cached?: boolean
}

export async function summarizeStory(req: SummarizeRequest): Promise<string> {
  const text = await send(`/api/reader/summarize`, http.RequestMethod.POST, JSON.stringify(req))
  const res = JSON.parse(text) as SummarizeResponse
  return res.summary
}

export interface ReaderQuota {
  used: number
  limit: number
  remaining: number
  isPro: boolean
}

export async function fetchQuota(): Promise<ReaderQuota> {
  const text = await send('/api/reader/quota', http.RequestMethod.GET)
  return JSON.parse(text) as ReaderQuota
}
