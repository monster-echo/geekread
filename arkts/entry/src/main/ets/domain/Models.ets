export interface BrandConfig {
  appName: string
  tagline: string
  primaryColor: string
}

export interface SplashConfig {
  id: string
  title: string
  description: string
  badge: string
  actionLabel: string
  imageUrl: string | null
  videoUrl: string | null
  linkUrl: string | null
  skippable: boolean
  durationSeconds: number
}

export interface MembershipTier {
  id: string
  name: string
  summary: string
  recommended: boolean
  accent: string
  entitlements: string[]
}

export interface BillingPlan {
  id: string
  tierId: string
  name: string
  interval: string
  priceMinor: number
  currency: string
  provider: string
  storeProductMapping?: StoreProductMapping
}

export interface LegalDocument {
  type: string
  locale: string
  revision: string
  title: string
  content: string
  requiresReconsent: boolean
}

export interface SettingPolicy {
  visibility: string
  mutability: string
}

export interface SupportCategory {
  id: string
  label: string
}

export interface HelpArticle {
  id: string
  locale: string
  title: string
  body: string
}

export interface SupportConfig {
  enabled: boolean
  market: string
  dataRegion: string
  categories: SupportCategory[]
  help: HelpArticle[]
}

export interface RuntimeConfig {
  schemaVersion: number
  version: number
  cacheTtlSeconds: number
  brand: BrandConfig
  splash: SplashConfig | null
  legal: LegalDocument[]
  settingsPolicy: Record<string, SettingPolicy>
  features: Record<string, boolean>
  tiers: MembershipTier[]
  plans: BillingPlan[]
  support: SupportConfig
}

export interface UsageScreen {
  screenId: string
  views: number
  durationMs: number
}

export interface UsageSummary {
  sessions: number
  screenViews: number
  activeMinutes: number
  screens: UsageScreen[]
}

export interface CouponView {
  id: string
  code: string
  title: string
  discountLabel: string
  expiresAt: string | null
  usedAt: string | null
  createdAt: string
}

export interface ReferralView {
  code: string
  invited: number
  shareUrl: string
}

export interface SessionView {
  id: string
  deviceName: string
  current: boolean
  createdAt: string
  lastSeenAt: string
}

export interface OrderView {
  id: string
  planId: string
  status: OrderStatus
  amountMinor: number
  currency: string
  provider: string
  createdAt: string
  completedAt: string | null
}

export interface NotificationView {
  id: string
  type: string
  title: string
  body: string
  route: string | null
  readAt: string | null
  createdAt: string
}

export interface SupportTicket {
  id: string
  category: string
  severity: string
  subject: string
  status: string
  locale: string
  market: string
  dataRegion: string
  queueId: string
  createdAt: string
  updatedAt: string
}

export interface SupportMessage {
  id: string
  authorType: string
  body: string
  createdAt: string
}

export interface SupportTicketDetail extends SupportTicket {
  messages: SupportMessage[]
}

export interface ProductFeedback {
  id: string
  category: string
  title: string
  body: string
  rating: number | null
  status: string
  market: string
  dataRegion: string
  queueId: string
  createdAt: string
  updatedAt: string
}

export interface AppUser {
  id: string
  email: string
  username: string
  displayName: string
  bio: string
  avatarUrl: string | null
  tierId: string
  settings: Record<string, string | number | boolean>
  emailVerified: boolean
  consentVersion: string | null
  createdAt: string
}

export interface BootstrapPayload {
  config: RuntimeConfig
  user: AppUser | null
  authProviders: Record<string, boolean>
  authProviderPolicy: Record<string, boolean>
  authProviderConfig: Record<string, Object>
  serverTime: string
  apiVersion: string
}

export interface AuthPayload {
  token: string
  refreshToken: string
  user: AppUser
}

export interface ApiEnvelope<T> {
  data: T
}

export interface ApiErrorBody {
  error: ApiError
}

export interface ApiError {
  code: string
  message: string
  retryable: boolean
  traceId: string
  fieldErrors?: Record<string, string[]>
  retryAfterSeconds?: number
}

export interface SignInInput {
  identifier: string
  password: string
  deviceName: string
}

export interface SignUpInput {
  email: string
  password: string
  deviceName: string
  username: string
  consentVersion: string
}

export interface DeleteAccountInput {
  password: string
  confirmation: string
}

export interface PhoneCodeInput {
  phone: string
}

export interface PhoneVerifyInput extends PhoneCodeInput {
  code: string
  deviceName: string
}

export interface FeedbackInput {
  category: string
  title: string
  body: string
  rating: number
}

export interface CreateTicketInput {
  category: string
  severity: string
  subject: string
  message: string
}

export interface StoreProductMapping {
  apple?: string
  google?: string
  hms?: string
}

export interface StoreProduct {
  storeProductId: string
  title?: string
}

export interface PurchaseResult {
  storeProductId: string
  receipt: Record<string, string | boolean | null>
}

export interface Entitlement {
  key: string
  expiresAt: string | null
}

export interface Subscription {
  planId: string
  status: string
  renewAt: string | null
}

export interface MembershipCurrent {
  tier: string | null
  entitlements: Entitlement[]
  subscription: Subscription | null
}

export interface CreateOrderResult {
  orderId: string
  storeProductId: string
  status: string
}

export enum OrderStatus {
  Pending = 'pending',
  Processing = 'processing',
  Success = 'success',
  Failed = 'failed',
  Refunded = 'refunded'
}

export function parseOrderStatus(value: string): OrderStatus {
  if (value === 'pending') return OrderStatus.Pending
  if (value === 'processing') return OrderStatus.Processing
  if (value === 'success') return OrderStatus.Success
  if (value === 'failed') return OrderStatus.Failed
  if (value === 'refunded') return OrderStatus.Refunded
  return OrderStatus.Pending
}

export enum PurchaseStatus {
  Idle = 'idle',
  Loading = 'loading',
  Success = 'success',
  Failed = 'failed',
  Error = 'error',
  Offline = 'offline',
  Unauthorized = 'unauthorized'
}
