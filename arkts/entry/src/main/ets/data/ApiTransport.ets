import http from '@ohos.net.http'
import { TelemetryBatch, TelemetryValue } from '../telemetry/Telemetry'
import {
  ApiEnvelope,
  ApiErrorBody,
  AuthPayload,
  CreateTicketInput,
  DeleteAccountInput,
  FeedbackInput,
  PhoneCodeInput,
  PhoneVerifyInput,
  SignInInput,
  SignUpInput
} from '../domain/Models'

const API_BASE: string = 'http://192.168.20.120:3210'
const APP_ID: string = 'geekread'
const APP_ENVIRONMENT: string = 'development'

export interface SocialSignInInput {
  provider: string
  deviceName: string
  idToken?: string
  authorizationCode?: string
  redirectUri?: string
  codeVerifier?: string
}

export interface VerifyPurchaseBody {
  receipt: Record<string, string | boolean | null>
  orderId?: string
}

export interface RestorePurchasesBody {
  receipts: Record<string, string | boolean | null>[]
}

export type ApiRequestBody =
  Record<string, string | number | boolean> |
  SignInInput | SignUpInput | DeleteAccountInput |
  PhoneCodeInput | PhoneVerifyInput | FeedbackInput |
  CreateTicketInput | SocialSignInInput |
  VerifyPurchaseBody | RestorePurchasesBody

interface TelemetryEventEnvelope {
  eventId: string
  name: string
  screenId: string
  occurredAt: string
  configVersion: number
  properties: Record<string, TelemetryValue>
}

export class ApiFailure extends Error {
  readonly code: string
  readonly status: number
  readonly retryable: boolean
  readonly fieldErrors?: Record<string, string[]>

  constructor(
    code: string,
    message: string,
    status: number,
    retryable: boolean,
    fieldErrors?: Record<string, string[]>
  ) {
    super(message)
    this.code = code
    this.status = status
    this.retryable = retryable
    this.fieldErrors = fieldErrors
  }
}

export class ApiTransport {
  private token: string = ''
  private refreshToken: string = ''
  private installationId: string = ''
  private language: string = 'zh-CN'
  private refreshInFlight: Promise<boolean> | null = null
  private sessionExpiredCallback: (() => void) | null = null

  constructor() {
    if (APP_ID.length === 0) throw new Error('APP_ID is required')
    if (APP_ENVIRONMENT.length === 0) throw new Error('APP_ENVIRONMENT is required')
  }

  setToken(value: string): void {
    this.token = value
  }

  setRefreshToken(value: string): void {
    this.refreshToken = value
  }

  setInstallationId(value: string): void {
    this.installationId = value
  }

  setLanguage(value: string): void {
    this.language = value
  }

  setSessionExpiredCallback(callback: (() => void) | null): void {
    this.sessionExpiredCallback = callback
  }

  async request<T>(
    path: string,
    method: http.RequestMethod,
    body?: ApiRequestBody,
    extraHeaders?: Record<string, string>,
    retried: boolean = false
  ): Promise<T> {
    const client = http.createHttp()
    try {
      const merged = this.headers()
      if (extraHeaders !== undefined) {
        const keys = Object.keys(extraHeaders)
        for (let i = 0; i < keys.length; i++) {
          merged[keys[i]] = extraHeaders[keys[i]]
        }
      }
      const response = await client.request(`${API_BASE}${path}`, {
        method,
        header: merged,
        extraData: body === undefined ? undefined : JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 5000
      })
      const text = String(response.result)
      if (response.responseCode === 401 && !retried && await this.refreshSession()) {
        return this.request<T>(path, method, body, extraHeaders, true)
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        if (response.responseCode === 401 && !retried) {
          this.sessionExpiredCallback?.()
        }
        throw this.parseFailure(text, response.responseCode)
      }
      return (JSON.parse(text) as ApiEnvelope<T>).data
    } finally {
      client.destroy()
    }
  }

  private parseFailure(text: string, status: number): ApiFailure {
    try {
      const failure = JSON.parse(text) as ApiErrorBody
      const error = failure.error
      return new ApiFailure(
        error.code,
        specificErrorMessage(error.message, error.fieldErrors),
        status,
        error.retryable,
        error.fieldErrors
      )
    } catch (error) {
      if (error instanceof ApiFailure) return error
      return new ApiFailure(
        'INVALID_RESPONSE',
        status >= 500 ? '服务暂时不可用，请稍后重试' : '服务返回了无法识别的错误',
        status,
        status >= 500
      )
    }
  }

  async telemetry(batch: TelemetryBatch): Promise<boolean> {
    const payload = JSON.stringify({
      anonymousId: batch.anonymousId,
      sessionId: batch.sessionId,
      events: batch.events.map((event): TelemetryEventEnvelope => ({
        eventId: event.eventId,
        name: event.name,
        screenId: event.screenId,
        occurredAt: event.occurredAt,
        configVersion: event.configVersion,
        properties: this.toRecord(event.properties)
      }))
    })
    const client = http.createHttp()
    try {
      const response = await client.request(`${API_BASE}/api/v1/telemetry/events`, {
        method: http.RequestMethod.POST,
        header: this.headers(),
        extraData: payload,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 5000
      })
      return response.responseCode >= 200 && response.responseCode < 300
    } catch (error) {
      return false
    } finally {
      client.destroy()
    }
  }

  private async refreshSession(): Promise<boolean> {
    if (this.refreshInFlight === null) this.refreshInFlight = this.performRefresh()
    const current = this.refreshInFlight
    try {
      return await current
    } finally {
      this.refreshInFlight = null
    }
  }

  private async performRefresh(): Promise<boolean> {
    if (this.refreshToken.length === 0) return false
    const client = http.createHttp()
    try {
      const response = await client.request(`${API_BASE}/api/v1/auth/refresh`, {
        method: http.RequestMethod.POST,
        header: this.headers(),
        extraData: JSON.stringify({ refreshToken: this.refreshToken }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 5000,
        readTimeout: 5000
      })
      if (response.responseCode < 200 || response.responseCode >= 300) return false
      const payload = JSON.parse(String(response.result)) as ApiEnvelope<AuthPayload>
      if (!payload.data.token || !payload.data.refreshToken) return false
      this.token = payload.data.token
      this.refreshToken = payload.data.refreshToken
      return true
    } catch (error) {
      return false
    } finally {
      client.destroy()
    }
  }

  private headers(): Record<string, string> {
    const values: Record<string, string> = {
      'content-type': 'application/json',
      'accept-language': this.language,
      'x-app-id': APP_ID,
      'x-app-environment': APP_ENVIRONMENT,
      'x-platform': 'harmonyos',
      'x-app-version': '1.0.0'
    }
    if (this.token.length > 0) values['authorization'] = `Bearer ${this.token}`
    if (this.installationId.length > 0) values['x-installation-id'] = this.installationId
    return values
  }

  private toRecord(map: Map<string, TelemetryValue>): Record<string, TelemetryValue> {
    const record: Record<string, TelemetryValue> = {}
    map.forEach((value, key) => { record[key] = value })
    return record
  }
}

export function specificErrorMessage(
  fallback: string,
  fieldErrors?: Record<string, string[]>
): string {
  if (fieldErrors === undefined) return fallback
  const keys = Object.keys(fieldErrors)
  const messages: string[] = []
  for (let i = 0; i < keys.length; i++) {
    const values = fieldErrors[keys[i]]
    for (let j = 0; j < values.length; j++) {
      if (values[j].length > 0 && !messages.includes(values[j])) messages.push(values[j])
    }
  }
  return messages.length > 0 ? messages.join('；') : fallback
}
