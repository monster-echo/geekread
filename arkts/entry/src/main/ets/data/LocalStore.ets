import common from '@ohos.app.ability.common'
import preferences from '@ohos.data.preferences'
import { RuntimeConfig } from '../domain/Models'

const STORE_NAME: string = 'mobileui.runtime'
const TOKEN_KEY: string = 'sessionToken'
const REFRESH_TOKEN_KEY: string = 'sessionRefreshToken'
const CONFIG_KEY: string = 'runtimeConfig'
const INSTALLATION_KEY: string = 'installationId'
const THEME_KEY: string = 'preference.theme'
const LANGUAGE_KEY: string = 'preference.language'
const TEXT_SCALE_KEY: string = 'preference.textScale'
const TRANSLATION_DISPLAY_KEY: string = 'preference.translationDisplay'

export class LocalStore {
  private store?: preferences.Preferences

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.store = await preferences.getPreferences(context, STORE_NAME)
  }

  readToken(): string {
    return String(this.store?.getSync(TOKEN_KEY, '') ?? '')
  }

  saveToken(token: string): void {
    this.store?.putSync(TOKEN_KEY, token)
    this.store?.flush()
  }

  readRefreshToken(): string {
    return String(this.store?.getSync(REFRESH_TOKEN_KEY, '') ?? '')
  }

  saveRefreshToken(token: string): void {
    this.store?.putSync(REFRESH_TOKEN_KEY, token)
    this.store?.flush()
  }

  readConfig(): RuntimeConfig | null {
    const value = String(this.store?.getSync(CONFIG_KEY, '') ?? '')
    if (value.length === 0) {
      return null
    }
    try {
      return JSON.parse(value) as RuntimeConfig
    } catch (error) {
      return null
    }
  }

  saveConfig(config: RuntimeConfig): void {
    this.store?.putSync(CONFIG_KEY, JSON.stringify(config))
    this.store?.flush()
  }

  /** 通用 JSON 缓存读取（key 由调用方约定，序列化失败/缺失返回 null）。 */
  readJson<T>(key: string): T | null {
    const value = String(this.store?.getSync(key, '') ?? '')
    if (value.length === 0) {
      return null
    }
    try {
      return JSON.parse(value) as T
    } catch (error) {
      return null
    }
  }

  /** 通用 JSON 缓存写入。 */
  saveJson(key: string, value: object): void {
    this.store?.putSync(key, JSON.stringify(value))
    this.store?.flush()
  }

  readTheme(): string {
    return String(this.store?.getSync(THEME_KEY, 'system') ?? 'system')
  }

  readLanguage(): string {
    return String(this.store?.getSync(LANGUAGE_KEY, 'zh-CN') ?? 'zh-CN')
  }

  readTextScale(): number {
    return Number(this.store?.getSync(TEXT_SCALE_KEY, 1) ?? 1)
  }

  readTranslationDisplay(): string {
    return String(this.store?.getSync(TRANSLATION_DISPLAY_KEY, 'both') ?? 'both')
  }

  savePreference(key: string, value: string | number): void {
    if (key === 'theme') this.store?.putSync(THEME_KEY, value)
    if (key === 'language') this.store?.putSync(LANGUAGE_KEY, value)
    if (key === 'textScale') this.store?.putSync(TEXT_SCALE_KEY, value)
    if (key === 'translationDisplay') this.store?.putSync(TRANSLATION_DISPLAY_KEY, value)
    this.store?.flush()
  }

  installationId(): string {
    const existing = String(this.store?.getSync(INSTALLATION_KEY, '') ?? '')
    if (existing.length >= 8) return existing
    const value = `harmony-${Date.now()}-${Math.floor(Math.random() * 1000000)}`
    this.store?.putSync(INSTALLATION_KEY, value)
    this.store?.flush()
    return value
  }

  configBytes(): number {
    return String(this.store?.getSync(CONFIG_KEY, '') ?? '').length
  }

  clearRuntimeCache(): void {
    this.store?.deleteSync(CONFIG_KEY)
    this.store?.flush()
  }
}

export const localStore: LocalStore = new LocalStore()
