import http from '@ohos.net.http'
import { localStore } from '../../../data/LocalStore'

// MobileStarter server（共享通用后端）基址。ArkTS 无 env 系统，部署时改本常量。
const MOBILE_STARTER_BASE: string = 'http://192.168.20.120:3210'
const APP_ID: string = 'geekread'
const APP_ENV: string = 'development'

interface EntitlementResponse {
  token: string | null
  expiresAt: number | null
}

let cached: EntitlementResponse = { token: null, expiresAt: null }

export function clearEntitlementCache(): void {
  cached = { token: null, expiresAt: null }
}

/** 拉取并缓存 Pro 权益 JWT（MobileStarter 签发）。未登录或无 Pro 返回空串。 */
export async function getEntitlementToken(): Promise<string> {
  const now: number = Math.floor(Date.now() / 1000)
  if (cached.token !== null && cached.expiresAt !== null && cached.expiresAt - now > 60) {
    return cached.token
  }
  const session: string = localStore.readToken()
  if (session.length === 0) return ''
  const client = http.createHttp()
  try {
    const response = await client.request(`${MOBILE_STARTER_BASE}/api/v1/me/entitlement`, {
      method: http.RequestMethod.POST,
      header: {
        'authorization': `Bearer ${session}`,
        'x-app-id': APP_ID,
        'x-app-environment': APP_ENV,
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 5000,
      readTimeout: 5000,
    })
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return cached.token ?? ''
    }
    const body = JSON.parse(String(response.result)) as EntitlementResponse
    cached = { token: body.token, expiresAt: body.expiresAt }
    return body.token ?? ''
  } catch (e) {
    return cached.token ?? ''
  } finally {
    client.destroy()
  }
}
