import http from '@ohos.net.http'
import { localStore } from '../../../data/LocalStore'
import { HNItem, Story, TargetLanguage } from '../domain/Models'
import { toStory } from '../domain/Models'
import { getEntitlementToken } from './Entitlement'

const GEEK_READER_BASE: string = 'http://192.168.20.120:8787'

export interface TranslateEntry {
  key: string
  text: string
}

export interface TranslateRequest {
  targetLanguage: TargetLanguage
  entries: TranslateEntry[]
}

export interface TranslateResult {
  key: string
  translation?: string
  cached?: boolean
  error?: string
}

export interface TranslateResponse {
  results: TranslateResult[]
  remainingTranslations?: number
}

export interface StoriesResponse {
  ids: number[]
  cached: boolean
  stale: boolean
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
      readTimeout: 15000,
    })
    const text = String(response.result)
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`geekreader_${response.responseCode}`)
    }
    return text
  } finally {
    client.destroy()
  }
}

export async function fetchStories(type: string): Promise<StoriesResponse> {
  const text = await send(`/api/reader/stories?type=${type}`, http.RequestMethod.GET)
  return JSON.parse(text) as StoriesResponse
}

export async function fetchItems(ids: number[]): Promise<ItemsResponse> {
  const text = await send(`/api/reader/items`, http.RequestMethod.POST, JSON.stringify({ ids }))
  return JSON.parse(text) as ItemsResponse
}

export async function translateBatch(req: TranslateRequest): Promise<TranslateResponse> {
  const text = await send(`/api/translate`, http.RequestMethod.POST, JSON.stringify(req))
  return JSON.parse(text) as TranslateResponse
}

export async function fetchStoriesResolved(ids: number[]): Promise<Story[]> {
  const res = await fetchItems(ids)
  const out: Story[] = []
  for (let i = 0; i < res.items.length; i++) {
    const s = toStory(res.items[i])
    if (s !== null) out.push(s)
  }
  return out
}
