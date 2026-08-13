import http from '@ohos.net.http'
import { TelemetryBatch } from '../telemetry/Telemetry'
import {
  ApiFailure,
  ApiRequestBody,
  ApiTransport,
  RestorePurchasesBody,
  SocialSignInInput,
  VerifyPurchaseBody
} from './ApiTransport'
import {
  AppUser,
  AuthPayload,
  BootstrapPayload,
  CouponView,
  CreateOrderResult,
  CreateTicketInput,
  DeleteAccountInput,
  FeedbackInput,
  HelpArticle,
  MembershipCurrent,
  NotificationView,
  OrderStatus,
  OrderView,
  PhoneCodeInput,
  PhoneVerifyInput,
  parseOrderStatus,
  ReferralView,
  SessionView,
  SignInInput,
  SignUpInput,
  SupportTicket,
  SupportTicketDetail,
  SupportMessage,
  UsageSummary
} from '../domain/Models'

export { ApiFailure } from './ApiTransport'

export class ApiClient {
  private transport: ApiTransport = new ApiTransport()

  setToken(token: string): void {
    this.transport.setToken(token)
  }

  setRefreshToken(token: string): void {
    this.transport.setRefreshToken(token)
  }

  setInstallationId(value: string): void {
    this.transport.setInstallationId(value)
  }

  setLanguage(value: string): void {
    this.transport.setLanguage(value)
  }

  // Set by AppStore so an unrecoverable session expiry clears the user and
  // returns to the sign-in guard instead of looping on failing requests.
  setSessionExpiredCallback(callback: (() => void) | null): void {
    this.transport.setSessionExpiredCallback(callback)
  }

  bootstrap(): Promise<BootstrapPayload> {
    return this.request<BootstrapPayload>('/api/v1/bootstrap', http.RequestMethod.GET)
  }

  signIn(identifier: string, password: string): Promise<AuthPayload> {
    const input: SignInInput = { identifier, password, deviceName: 'HarmonyOS · MobileUI' }
    return this.request<AuthPayload>('/api/v1/auth/sign-in', http.RequestMethod.POST, input)
  }

  signUp(email: string, password: string, username: string, consentVersion: string):
    Promise<AuthPayload> {
    const input: SignUpInput = {
      email,
      password,
      username,
      consentVersion,
      deviceName: 'HarmonyOS · MobileUI'
    }
    return this.request<AuthPayload>('/api/v1/auth/sign-up', http.RequestMethod.POST, input)
  }

  verifyEmail(email: string, code: string): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      '/api/v1/auth/verify-email',
      http.RequestMethod.POST,
      { email, code }
    ).then(result => result['verified'] === true)
  }

  resendEmailVerification(email: string): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      '/api/v1/auth/verify-email/resend',
      http.RequestMethod.POST,
      { email }
    ).then(result => result['accepted'] === true)
  }

  signOut(): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      '/api/v1/auth/sign-out',
      http.RequestMethod.POST
    ).then(result => result['signedOut'] === true)
  }

  signOutAll(): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      '/api/v1/auth/sign-out-all',
      http.RequestMethod.POST
    ).then(result => result['signedOut'] === true)
  }

  requestPhoneCode(phone: string): Promise<boolean> {
    const input: PhoneCodeInput = { phone }
    return this.request<Record<string, boolean>>(
      '/api/v1/auth/phone/request',
      http.RequestMethod.POST,
      input
    ).then(result => result['accepted'] === true)
  }

  verifyPhoneCode(phone: string, code: string): Promise<AuthPayload> {
    const input: PhoneVerifyInput = {
      phone,
      code,
      deviceName: 'HarmonyOS · MobileUI'
    }
    return this.request<AuthPayload>(
      '/api/v1/auth/phone/verify',
      http.RequestMethod.POST,
      input
    )
  }

  socialSignIn(
    provider: string,
    idToken: string,
    authorizationCode: string,
    redirectUri: string,
    codeVerifier: string
  ): Promise<AuthPayload> {
    const body: SocialSignInInput = {
      provider,
      deviceName: 'HarmonyOS · MobileUI'
    }
    if (idToken.length > 0) body.idToken = idToken
    if (authorizationCode.length > 0) body.authorizationCode = authorizationCode
    if (redirectUri.length > 0) body.redirectUri = redirectUri
    if (codeVerifier.length > 0) body.codeVerifier = codeVerifier
    return this.request<AuthPayload>(
      '/api/v1/auth/social', http.RequestMethod.POST, body
    )
  }

  requestPasswordReset(email: string): Promise<boolean> {
    return this.request<Record<string, string | number | boolean>>(
      '/api/v1/auth/password/forgot', http.RequestMethod.POST, { email }
    ).then(result => result['accepted'] === true)
  }

  verifyPasswordReset(email: string, code: string): Promise<string> {
    return this.request<Record<string, string | number>>(
      '/api/v1/auth/password/verify', http.RequestMethod.POST, { email, code }
    ).then(result => String(result['resetToken'] ?? ''))
  }

  resetPassword(resetToken: string, newPassword: string): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      '/api/v1/auth/password/reset', http.RequestMethod.POST,
      { resetToken, newPassword }
    ).then(result => result['changed'] === true)
  }

  saveSettings(patch: Record<string, string | number | boolean>):
    Promise<Record<string, string | number | boolean>> {
    return this.request<Record<string, string | number | boolean>>(
      '/api/v1/me/settings',
      http.RequestMethod.PUT,
      patch
    )
  }

  changePassword(currentPassword: string, newPassword: string): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      '/api/v1/me/change-password',
      http.RequestMethod.POST,
      { currentPassword, newPassword }
    ).then(result => result['changed'] === true)
  }

  updateProfile(username: string, displayName: string, bio: string, avatarUrl: string): Promise<AppUser> {
    return this.request<AppUser>(
      '/api/v1/me/profile',
      http.RequestMethod.PUT,
      { username, displayName, bio, avatarUrl }
    )
  }

  sessions(): Promise<SessionView[]> {
    return this.request<SessionView[]>('/api/v1/me/sessions', http.RequestMethod.GET)
  }

  revokeSession(id: string): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      `/api/v1/me/sessions/${id}`,
      http.RequestMethod.DELETE
    ).then(result => result['revoked'] === true)
  }

  orders(): Promise<OrderView[]> {
    return this.request<OrderView[]>('/api/v1/orders', http.RequestMethod.GET)
  }

  createOrder(planId: string, idempotencyKey: string): Promise<CreateOrderResult> {
    return this.request<CreateOrderResult>(
      '/api/v1/orders',
      http.RequestMethod.POST,
      { planId },
      { 'Idempotency-Key': idempotencyKey }
    )
  }

  verifyPurchase(orderId: string | null, receipt: Record<string, string | boolean | null>):
    Promise<OrderView> {
    const body: VerifyPurchaseBody = { receipt }
    if (orderId != null) body.orderId = orderId
    return this.request<OrderView>(
      '/api/v1/purchases/verify', http.RequestMethod.POST, body
    ).then((order: OrderView): OrderView => ({
      id: order.id,
      planId: order.planId,
      status: parseOrderStatus(String(order.status)),
      amountMinor: order.amountMinor,
      currency: order.currency,
      provider: order.provider,
      createdAt: order.createdAt,
      completedAt: order.completedAt
    }))
  }

  restorePurchases(receipts: Record<string, string | boolean | null>[]): Promise<string[]> {
    const body: RestorePurchasesBody = { receipts }
    return this.request<Record<string, string[]>>(
      '/api/v1/purchases/restore', http.RequestMethod.POST, body
    ).then(result => result['entitlements'] ?? [])
  }

  membershipCurrent(): Promise<MembershipCurrent> {
    return this.request<MembershipCurrent>('/api/v1/membership/current', http.RequestMethod.GET)
  }

  entitlements(): Promise<string[]> {
    return this.request<Record<string, string[]>>(
      '/api/v1/membership/entitlements', http.RequestMethod.GET
    ).then(result => result['keys'] ?? [])
  }

  notifications(): Promise<NotificationView[]> {
    return this.request<NotificationView[]>('/api/v1/notifications', http.RequestMethod.GET)
  }

  markAllNotificationsRead(): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      '/api/v1/notifications', http.RequestMethod.PUT
    ).then(result => result['allRead'] === true)
  }

  markNotificationRead(id: string): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      `/api/v1/notifications/${id}`, http.RequestMethod.PUT
    ).then(result => result['read'] === true)
  }

  deleteNotification(id: string): Promise<boolean> {
    return this.request<Record<string, boolean>>(
      `/api/v1/notifications/${id}`, http.RequestMethod.DELETE
    ).then(result => result['deleted'] === true)
  }

  submitFeedback(
    title: string,
    body: string,
    category: string = 'suggestion',
    rating: number = 5
  ): Promise<boolean> {
    const input: FeedbackInput = { category, title, body, rating }
    return this.request<Record<string, string | number>>(
      '/api/v1/support/feedback',
      http.RequestMethod.POST,
      input
    ).then(result => String(result['id'] ?? '').length > 0)
  }

  help(): Promise<HelpArticle[]> {
    return this.request<HelpArticle[]>('/api/v1/support/help', http.RequestMethod.GET)
  }

  tickets(): Promise<SupportTicket[]> {
    return this.request<SupportTicket[]>('/api/v1/support/tickets', http.RequestMethod.GET)
  }

  ticket(id: string): Promise<SupportTicketDetail> {
    return this.request<SupportTicketDetail>(
      `/api/v1/support/tickets/${id}`, http.RequestMethod.GET
    )
  }

  createTicket(input: CreateTicketInput): Promise<SupportTicket> {
    return this.request<SupportTicket>(
      '/api/v1/support/tickets', http.RequestMethod.POST, input
    )
  }

  reply(ticketId: string, message: string): Promise<SupportMessage> {
    return this.request<SupportMessage>(
      `/api/v1/support/tickets/${ticketId}/messages`,
      http.RequestMethod.POST,
      { message }
    )
  }

  usage(): Promise<UsageSummary> {
    return this.request<UsageSummary>('/api/v1/me/usage', http.RequestMethod.GET)
  }

  coupons(): Promise<CouponView[]> {
    return this.request<CouponView[]>('/api/v1/me/coupons', http.RequestMethod.GET)
  }

  referral(): Promise<ReferralView> {
    return this.request<ReferralView>('/api/v1/me/referral', http.RequestMethod.GET)
  }

  deleteAccount(password: string): Promise<boolean> {
    const input: DeleteAccountInput = { password, confirmation: 'DELETE' }
    return this.request<Record<string, boolean>>(
      '/api/v1/me/deletion',
      http.RequestMethod.DELETE,
      input
    ).then(result => result['deleted'] === true)
  }

  telemetry(batch: TelemetryBatch): Promise<boolean> {
    return this.transport.telemetry(batch)
  }

  private async request<T>(
    path: string,
    method: http.RequestMethod,
    body?: ApiRequestBody,
    extraHeaders?: Record<string, string>
  ): Promise<T> {
    return this.transport.request<T>(path, method, body, extraHeaders)
  }
}

export const apiClient: ApiClient = new ApiClient()
