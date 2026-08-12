import common from '@ohos.app.ability.common'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { apiClient, ApiFailure } from '../data/ApiClient'
import { localStore } from '../data/LocalStore'
import { AppUser, AuthPayload, OrderStatus, OrderView, PurchaseStatus, RuntimeConfig }
  from '../domain/Models'
import { RemoteDataStore } from './RemoteDataStore'
import { MockPaymentProvider } from '../payment/MockPaymentProvider'
import { AppRoute } from '../navigation/AppRoute'
import { telemetry, TelemetryConfig } from '../telemetry/Telemetry'
import { AppTelemetrySink } from '../telemetry/AppTelemetrySink'
import { guardRoute } from '../navigation/RouteGuard'

@Observed
export class AppStore {
  // Resolves the route names carried by notification deep links back to the
  // enum. ArkTS forbids dynamic enum indexing, so this is an explicit map.
  static readonly ROUTE_BY_NAME: Record<string, AppRoute> = {
    'Logo': AppRoute.Logo, 'Promo': AppRoute.Promo, 'Onboarding': AppRoute.Onboarding,
    'Home': AppRoute.Home, 'SignIn': AppRoute.SignIn, 'SignUp': AppRoute.SignUp,
    'PhoneSignIn': AppRoute.PhoneSignIn, 'ForgotPassword': AppRoute.ForgotPassword,
    'VerifyEmail': AppRoute.VerifyEmail, 'ResetPassword': AppRoute.ResetPassword,
    'Profile': AppRoute.Profile, 'ProfileEdit': AppRoute.ProfileEdit,
    'Statistics': AppRoute.Statistics, 'Invite': AppRoute.Invite, 'Coupons': AppRoute.Coupons,
    'Membership': AppRoute.Membership, 'MembershipPlans': AppRoute.MembershipPlans,
    'Checkout': AppRoute.Checkout, 'Orders': AppRoute.Orders, 'Settings': AppRoute.Settings,
    'AccountSecurity': AppRoute.AccountSecurity, 'Devices': AppRoute.Devices,
    'NotificationSettings': AppRoute.NotificationSettings, 'Privacy': AppRoute.Privacy,
    'General': AppRoute.General, 'Appearance': AppRoute.Appearance, 'Language': AppRoute.Language,
    'TextSize': AppRoute.TextSize, 'Storage': AppRoute.Storage, 'Permissions': AppRoute.Permissions,
    'HelpFeedback': AppRoute.HelpFeedback, 'Legal': AppRoute.Legal,
    'TermsOfService': AppRoute.TermsOfService, 'PrivacyPolicy': AppRoute.PrivacyPolicy,
    'About': AppRoute.About,
    'DeleteAccount': AppRoute.DeleteAccount, 'NotificationCenter': AppRoute.NotificationCenter,
    'StateGallery': AppRoute.StateGallery, 'SupportTicket': AppRoute.SupportTicket,
    'NewSupportTicket': AppRoute.NewSupportTicket, 'ProductFeedback': AppRoute.ProductFeedback,
    'GeekReader': AppRoute.GeekReader, 'GeekReaderDetail': AppRoute.GeekReaderDetail,
    'geekReader.home': AppRoute.GeekReader, 'geekReader.story': AppRoute.GeekReaderDetail,
    'notifications.center': AppRoute.NotificationCenter, 'profile.home': AppRoute.Profile,
    'profile.edit': AppRoute.ProfileEdit, 'profile.statistics': AppRoute.Statistics,
    'profile.invite': AppRoute.Invite, 'profile.coupons': AppRoute.Coupons,
    'membership.home': AppRoute.Membership,
    'membership.plans': AppRoute.MembershipPlans, 'orders.list': AppRoute.Orders,
    'membership.checkout': AppRoute.Checkout, 'membership.orders': AppRoute.Orders,
    'settings.home': AppRoute.Settings, 'settings.accountSecurity': AppRoute.AccountSecurity,
    'settings.devices': AppRoute.Devices, 'settings.notifications': AppRoute.NotificationSettings,
    'settings.privacy': AppRoute.Privacy, 'settings.general': AppRoute.General,
    'settings.appearance': AppRoute.Appearance, 'settings.language': AppRoute.Language,
    'settings.textSize': AppRoute.TextSize, 'settings.storage': AppRoute.Storage,
    'settings.permissions': AppRoute.Permissions,
    'settings.helpFeedback': AppRoute.HelpFeedback, 'settings.legal': AppRoute.Legal,
    'settings.termsOfService': AppRoute.TermsOfService,
    'settings.privacyPolicy': AppRoute.PrivacyPolicy,
    'settings.about': AppRoute.About, 'support.home': AppRoute.HelpFeedback,
    'support.newTicket': AppRoute.NewSupportTicket
  }

  routeStack: AppRoute[] = [AppRoute.Logo]
  // 根 Navigation 的路径栈：唯一导航容器（Index 的 Navigation 持有）。
  pathStack: NavPathStack = new NavPathStack()
  signedIn: boolean = false
  online: boolean = true
  // bootstrapped：初始 bootstrap 是否完成（成功或失败）；品牌闪屏据此判断"配置拉取完成"。
  bootstrapped: boolean = false
  busy: boolean = false
  theme: string = 'system'
  language: string = 'zh-CN'
  geekReaderStoryId: number = -1
  textScale: number = 1
  config: RuntimeConfig | null = null
  user: AppUser | null = null
  toastMessage: string = ''
  toastError: boolean = false
  authProviders: Record<string, boolean> = {}
  authProviderPolicy: Record<string, boolean> = {}
  authProviderConfig: Record<string, Object> = {}
  recoveryEmail: string = ''
  resetToken: string = ''
  pendingRoute: AppRoute | null = null
  // payment
  purchaseStatus: PurchaseStatus = PurchaseStatus.Idle
  purchaseOrder: OrderView | null = null
  purchaseMessage: string = ''
  pendingPlanId: string = ''
  remote: RemoteDataStore = new RemoteDataStore()
  private context: common.UIAbilityContext | null = null
  private initialized: boolean = false
  private queuedEntryName: string | null = null
  private queuedEntryCold: boolean = false

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context
    await localStore.initialize(context)
    this.applyPreferences()
    apiClient.setInstallationId(localStore.installationId())
    const cached = localStore.readConfig()
    if (cached !== null) {
      this.config = cached
    }
    const token = localStore.readToken()
    apiClient.setToken(token)
    apiClient.setRefreshToken(localStore.readRefreshToken())
    apiClient.setSessionExpiredCallback(() => { this.handleSessionExpired() })
    try {
      const payload = await apiClient.bootstrap()
      this.config = payload.config
      this.user = payload.user
      this.authProviders = payload.authProviders
      this.authProviderPolicy = payload.authProviderPolicy
      this.authProviderConfig = payload.authProviderConfig
      this.signedIn = payload.user !== null
      this.online = true
      localStore.saveConfig(payload.config)
      this.cacheUserPreferences()
    } catch (error) {
      this.online = false
      this.showToast('当前使用离线配置', true)
    }
    this.configureTelemetry()
    this.applyPreferences()
    this.initialized = true
    this.bootstrapped = true
    if (this.queuedEntryName !== null) {
      const name = this.queuedEntryName
      const cold = this.queuedEntryCold
      this.queuedEntryName = null
      this.openEntryByName(name, cold)
    }
  }

  private configureTelemetry(): void {
    const config = new TelemetryConfig()
    config.configVersion = this.config?.version ?? 0
    telemetry.configure(config, new AppTelemetrySink())
  }

  private cacheUserPreferences(): void {
    const settings = this.user?.settings
    if (settings === undefined) return
    const theme = settings['theme']
    const language = settings['language']
    const textScale = settings['textScale']
    if (typeof theme === 'string') localStore.savePreference('theme', theme)
    if (typeof language === 'string') localStore.savePreference('language', language)
    if (typeof textScale === 'number') localStore.savePreference('textScale', textScale)
  }

  private applyPreferences(): void {
    if (this.context === null) return
    const theme = localStore.readTheme()
    const language = localStore.readLanguage() === 'en-US' ? 'en-US' : 'zh-CN'
    const textScale = Math.min(1.3, Math.max(0.9, localStore.readTextScale()))
    this.theme = theme
    this.language = language
    this.textScale = textScale
    const colorMode = theme === 'dark'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : theme === 'light'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    const application = this.context.getApplicationContext()
    application.setColorMode(colorMode)
    application.setLanguage(language)
    application.setFontSizeScale(textScale)
    apiClient.setLanguage(language)
  }

  get route(): AppRoute {
    const names: string[] = this.pathStack.getAllPathName()
    if (names.length > 0) {
      const last = names[names.length - 1]
      const idx = last.indexOf('route_')
      if (idx === 0) {
        const v = Number(last.substring(6))
        if (!Number.isNaN(v) && v >= 0) return v as AppRoute
      }
    }
    return this.routeStack[this.routeStack.length - 1]
  }

  get canGoBack(): boolean {
    return this.pathStack.getAllPathName().length > 1
  }

  navigate(route: AppRoute): void {
    const decision = guardRoute(route, this.signedIn, this.config)
    if (decision.pending !== null) this.pendingRoute = decision.pending
    if (decision.unavailable) this.showToast('当前 App 未启用此功能')
    // 根 Navigation：压栈，源页面保留。
    this.pathStack.pushPathByName(`route_${decision.route}`, decision.route)
    telemetry.screen(decision.route.toString())
  }

  // Resolves an in-app route name (from a notification deep link) back to the
  // enum and navigates; external URLs and unknown names are ignored.
  navigateByName(name: string | null): void {
    if (name === null || name.length === 0 || name.includes('://')) return
    const route = AppStore.ROUTE_BY_NAME[name]
    if (route === undefined) return
    this.navigate(route)
  }

  openEntryByName(name: string | null, cold: boolean): void {
    if (name === null || name.length === 0 || name.includes('://')) return
    if (!this.initialized) {
      this.queuedEntryName = name
      this.queuedEntryCold = cold
      return
    }
    const target = AppStore.ROUTE_BY_NAME[name]
    if (target === undefined) return
    const decision = guardRoute(target, this.signedIn, this.config)
    if (decision.pending !== null) this.pendingRoute = decision.pending
    if (decision.unavailable) this.showToast('当前 App 未启用此功能')
    if (cold) {
      this.pathStack.clear()
      this.pathStack.pushPathByName(`route_${decision.route}`, decision.route)
    } else if (this.route !== decision.route) {
      this.pathStack.pushPathByName(`route_${decision.route}`, decision.route)
    }
    telemetry.screen(decision.route.toString())
  }

  resume(): void {
    this.applyPreferences()
  }

  replaceAll(route: AppRoute): void {
    const decision = guardRoute(route, this.signedIn, this.config)
    if (decision.pending !== null) this.pendingRoute = decision.pending
    this.pathStack.clear()
    this.pathStack.pushPathByName(`route_${decision.route}`, decision.route)
    telemetry.screen(decision.route.toString())
  }

  replaceTop(route: AppRoute): void {
    const decision = guardRoute(route, this.signedIn, this.config)
    if (decision.pending !== null) this.pendingRoute = decision.pending
    this.pathStack.pop()
    this.pathStack.pushPathByName(`route_${decision.route}`, decision.route)
    telemetry.screen(decision.route.toString())
  }

  completeAuthentication(): void {
    const target = this.pendingRoute ?? AppRoute.Home
    this.pendingRoute = null
    this.replaceTop(target)
  }

  back(): void {
    this.pathStack.pop()
  }

  async signIn(email: string, password: string): Promise<boolean> {
    return this.authenticate(() => apiClient.signIn(email, password))
  }

  async signUp(email: string, password: string, username: string, consentVersion: string):
    Promise<boolean> {
    return this.authenticate(() => apiClient.signUp(email, password, username, consentVersion))
  }

  async verifyEmail(code: string): Promise<boolean> {
    if (this.user === null) return false
    try {
      const verified = await apiClient.verifyEmail(this.user.email, code)
      if (verified) this.user.emailVerified = true
      return verified
    } catch (error) {
      this.showApiError(error)
      return false
    }
  }

  async requestPhoneCode(phone: string): Promise<boolean> {
    return this.performBooleanRequest(() => apiClient.requestPhoneCode(phone))
  }

  async verifyPhoneCode(phone: string, code: string): Promise<boolean> {
    return this.authenticate(() => apiClient.verifyPhoneCode(phone, code))
  }

  async socialSignIn(
    provider: string,
    idToken: string,
    authorizationCode: string,
    redirectUri: string,
    codeVerifier: string
  ): Promise<boolean> {
    return this.authenticate(() => apiClient.socialSignIn(
      provider, idToken, authorizationCode, redirectUri, codeVerifier
    ))
  }

  async requestPasswordReset(email: string): Promise<boolean> {
    return this.performBooleanRequest(async () => {
      const accepted = await apiClient.requestPasswordReset(email)
      if (accepted) this.recoveryEmail = email
      return accepted
    })
  }

  async verifyPasswordReset(code: string): Promise<boolean> {
    return this.performBooleanRequest(async () => {
      this.resetToken = await apiClient.verifyPasswordReset(this.recoveryEmail, code)
      return this.resetToken.length > 0
    })
  }

  async resetPassword(newPassword: string): Promise<boolean> {
    return this.performBooleanRequest(async () => {
      const changed = await apiClient.resetPassword(this.resetToken, newPassword)
      if (changed) {
        this.recoveryEmail = ''
        this.resetToken = ''
      }
      return changed
    })
  }

  private async performBooleanRequest(operation: () => Promise<boolean>): Promise<boolean> {
    if (this.busy) return false
    this.busy = true
    try {
      return await operation()
    } catch (error) {
      this.showApiError(error)
      return false
    } finally {
      this.busy = false
    }
  }

  async signOut(): Promise<void> {
    try {
      await apiClient.signOut()
    } catch (error) {
      this.online = false
    }
    this.clearLocalSession()
    this.signedIn = false
    this.user = null
  }

  async signOutAll(): Promise<void> {
    try {
      await apiClient.signOutAll()
    } catch (error) {
      this.online = false
    }
    this.clearLocalSession()
    this.signedIn = false
    this.user = null
  }

  private clearLocalSession(): void {
    localStore.saveToken('')
    localStore.saveRefreshToken('')
    apiClient.setToken('')
    apiClient.setRefreshToken('')
  }

  private handleSessionExpired(): void {
    this.clearLocalSession()
    this.signedIn = false
    this.user = null
    this.replaceAll(AppRoute.SignIn)
  }

  async saveSetting(key: string, value: string | number | boolean): Promise<boolean> {
    if (this.busy) {
      return false
    }
    this.busy = true
    const patch: Record<string, string | number | boolean> = {}
    patch[key] = value
    // 本地偏好不依赖登录：未登录也立即生效。
    if (typeof value !== 'boolean') localStore.savePreference(key, value)
    if (this.user !== null) {
      this.user.settings[key] = value
    }
    this.applyPreferences()
    if (!this.signedIn) {
      this.busy = false
      return true
    }
    try {
      const settings = await apiClient.saveSettings(patch)
      if (this.user !== null) {
        this.user.settings = settings
      }
      this.cacheUserPreferences()
      this.applyPreferences()
      this.online = true
      this.showToast('设置已同步到服务端')
      return true
    } catch (error) {
      this.showApiError(error)
      return false
    } finally {
      this.busy = false
    }
  }

  async deleteAccount(password: string): Promise<boolean> {
    if (!this.signedIn || this.busy) {
      return false
    }
    this.busy = true
    try {
      if (!await apiClient.deleteAccount(password)) {
        return false
      }
      this.clearLocalSession()
      this.signedIn = false
      this.user = null
      this.showToast('账号已永久删除')
      return true
    } catch (error) {
      this.showApiError(error)
      return false
    } finally {
      this.busy = false
    }
  }

  async changePassword(currentPassword: string, newPassword: string): Promise<boolean> {
    if (!this.signedIn || this.busy) return false
    this.busy = true
    try {
      if (!await apiClient.changePassword(currentPassword, newPassword)) return false
      this.clearLocalSession()
      this.signedIn = false
      this.user = null
      this.showToast('密码已修改，请重新登录')
      return true
    } catch (error) {
      this.showApiError(error)
      return false
    } finally {
      this.busy = false
    }
  }

  async updateProfile(displayName: string, bio: string, avatarUrl: string): Promise<boolean> {
    if (!this.signedIn || this.busy) return false
    this.busy = true
    try {
      this.user = await apiClient.updateProfile(displayName, bio, avatarUrl)
      this.showToast('个人资料已同步到服务端')
      return true
    } catch (error) {
      this.showApiError(error)
      return false
    } finally {
      this.busy = false
    }
  }

  async submitFeedback(
    title: string,
    body: string,
    category: string = 'suggestion',
    rating: number = 5
  ): Promise<boolean> {
    if (this.busy) return false
    this.busy = true
    try {
      const submitted = await apiClient.submitFeedback(title, body, category, rating)
      if (submitted) this.showToast('意见反馈已提交')
      return submitted
    } catch (error) {
      this.showApiError(error)
      return false
    } finally {
      this.busy = false
    }
  }

  async createTicket(
    category: string, severity: string, subject: string, message: string
  ): Promise<boolean> {
    if (this.busy) return false
    this.busy = true
    try {
      const created = await apiClient.createTicket({ category, severity, subject, message })
      await this.remote.openTicket(created.id)
      this.navigate(AppRoute.SupportTicket)
      this.showToast('工单已提交')
      return true
    } catch (error) {
      this.showApiError(error)
      return false
    } finally {
      this.busy = false
    }
  }

  async replyTicket(message: string): Promise<boolean> {
    const detail = this.remote.ticketDetailState.data
    if (detail === undefined || this.busy) return false
    this.busy = true
    try {
      const sent = await apiClient.reply(detail.id, message)
      this.remote.appendReply(sent)
      return true
    } catch (error) {
      this.showApiError(error)
      return false
    } finally {
      this.busy = false
    }
  }

  async purchase(planId: string): Promise<boolean> {
    this.purchaseStatus = PurchaseStatus.Loading
    this.purchaseOrder = null
    this.purchaseMessage = ''
    try {
      const idempotencyKey: string =
        `ark-${Date.now()}-${Math.random().toString(36).slice(2)}`
      const order = await apiClient.createOrder(planId, idempotencyKey)
      const provider: MockPaymentProvider = new MockPaymentProvider()
      const result = await provider.purchase(order.storeProductId)
      const verified = await apiClient.verifyPurchase(order.orderId, result.receipt)
      this.purchaseOrder = verified
      this.purchaseStatus =
        verified.status === OrderStatus.Success ? PurchaseStatus.Success : PurchaseStatus.Failed
      if (verified.status === OrderStatus.Success) {
        // Best-effort membership refresh: re-bootstrap so the user tier reflects
        // the purchase. `initialize` needs the UIAbilityContext captured at boot.
        const context = this.context
        try {
          if (context !== null) { await this.initialize(context) }
        } catch (e) { /* best-effort membership refresh */ }
      }
      return verified.status === OrderStatus.Success
    } catch (error) {
      if (error instanceof ApiFailure && error.status === 401) {
        this.purchaseStatus = PurchaseStatus.Unauthorized
      } else if (error instanceof ApiFailure) {
        // server returned an error envelope (non-2xx)
        this.purchaseStatus = PurchaseStatus.Error
        this.purchaseMessage = error.message
      } else {
        // non-ApiFailure = transport/network failure (timeout/DNS) → offline
        this.purchaseStatus = PurchaseStatus.Offline
      }
      return false
    }
  }

  startCheckout(planId: string): void {
    this.purchaseStatus = PurchaseStatus.Idle
    this.pendingPlanId = planId
  }

  showToast(message: string, error: boolean = false): void {
    this.toastMessage = message
    this.toastError = error
    setTimeout(() => {
      if (this.toastMessage === message) {
        this.toastMessage = ''
      }
    }, 2400)
  }

  private async authenticate(
    operation: () => Promise<AuthPayload>
  ): Promise<boolean> {
    if (this.busy) {
      return false
    }
    this.busy = true
    try {
      const payload = await operation()
      localStore.saveToken(payload.token)
      apiClient.setToken(payload.token)
      localStore.saveRefreshToken(payload.refreshToken)
      apiClient.setRefreshToken(payload.refreshToken)
      this.user = payload.user
      this.signedIn = true
      this.online = true
      return true
    } catch (error) {
      this.showApiError(error)
      return false
    } finally {
      this.busy = false
    }
  }

  private showApiError(error: Error): void {
    if (error instanceof ApiFailure) {
      this.showToast(error.message, true)
      return
    }
    this.online = false
    this.showToast('网络连接失败，请稍后重试', true)
  }

}
