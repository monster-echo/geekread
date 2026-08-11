import { apiClient, ApiFailure } from '../data/ApiClient'
import {
  CouponView, HelpArticle, NotificationView, OrderView, ReferralView,
  SessionView, SupportMessage, SupportTicket, SupportTicketDetail, UsageSummary
} from '../domain/Models'
import { AsyncState, AsyncStatus } from './AsyncState'

@Observed
export class RemoteDataStore {
  usageState: AsyncState<UsageSummary> = new AsyncState<UsageSummary>(AsyncStatus.Idle)
  couponState: AsyncState<CouponView[]> = new AsyncState<CouponView[]>(AsyncStatus.Idle)
  referralState: AsyncState<ReferralView> = new AsyncState<ReferralView>(AsyncStatus.Idle)
  sessionState: AsyncState<SessionView[]> = new AsyncState<SessionView[]>(AsyncStatus.Idle)
  orderState: AsyncState<OrderView[]> = new AsyncState<OrderView[]>(AsyncStatus.Idle)
  notificationState: AsyncState<NotificationView[]> =
    new AsyncState<NotificationView[]>(AsyncStatus.Idle)
  helpState: AsyncState<HelpArticle[]> = new AsyncState<HelpArticle[]>(AsyncStatus.Idle)
  ticketListState: AsyncState<SupportTicket[]> = new AsyncState<SupportTicket[]>(AsyncStatus.Idle)
  ticketDetailState: AsyncState<SupportTicketDetail> =
    new AsyncState<SupportTicketDetail>(AsyncStatus.Idle)

  async loadUsage(): Promise<void> {
    this.usageState = new AsyncState<UsageSummary>(AsyncStatus.Loading)
    try {
      const value = await apiClient.usage()
      this.usageState = value.screens.length === 0
        ? new AsyncState<UsageSummary>(AsyncStatus.Empty)
        : new AsyncState<UsageSummary>(AsyncStatus.Success, value)
    } catch (error) { this.usageState = this.failure<UsageSummary>(error) }
  }

  async loadCoupons(): Promise<void> {
    this.couponState = new AsyncState<CouponView[]>(AsyncStatus.Loading)
    try {
      const value = await apiClient.coupons()
      this.couponState = value.length === 0
        ? new AsyncState<CouponView[]>(AsyncStatus.Empty)
        : new AsyncState<CouponView[]>(AsyncStatus.Success, value)
    } catch (error) { this.couponState = this.failure<CouponView[]>(error) }
  }

  async loadReferral(): Promise<void> {
    this.referralState = new AsyncState<ReferralView>(AsyncStatus.Loading)
    try {
      this.referralState = new AsyncState<ReferralView>(
        AsyncStatus.Success, await apiClient.referral())
    } catch (error) { this.referralState = this.failure<ReferralView>(error) }
  }

  async loadSessions(): Promise<void> {
    this.sessionState = new AsyncState<SessionView[]>(AsyncStatus.Loading)
    try {
      const value = await apiClient.sessions()
      this.sessionState = value.length === 0
        ? new AsyncState<SessionView[]>(AsyncStatus.Empty)
        : new AsyncState<SessionView[]>(AsyncStatus.Success, value)
    } catch (error) { this.sessionState = this.failure<SessionView[]>(error) }
  }

  async revokeSession(id: string): Promise<void> {
    if (!await apiClient.revokeSession(id) || this.sessionState.data === undefined) return
    const value = this.sessionState.data.filter(session => session.id !== id)
    this.sessionState = value.length === 0
      ? new AsyncState<SessionView[]>(AsyncStatus.Empty)
      : new AsyncState<SessionView[]>(AsyncStatus.Success, value)
  }

  async loadOrders(): Promise<void> {
    this.orderState = new AsyncState<OrderView[]>(AsyncStatus.Loading)
    try {
      const value = await apiClient.orders()
      this.orderState = value.length === 0
        ? new AsyncState<OrderView[]>(AsyncStatus.Empty)
        : new AsyncState<OrderView[]>(AsyncStatus.Success, value)
    } catch (error) { this.orderState = this.failure<OrderView[]>(error) }
  }

  async loadNotifications(): Promise<void> {
    this.notificationState = new AsyncState<NotificationView[]>(AsyncStatus.Loading)
    try {
      const value = await apiClient.notifications()
      this.notificationState = value.length === 0
        ? new AsyncState<NotificationView[]>(AsyncStatus.Empty)
        : new AsyncState<NotificationView[]>(AsyncStatus.Success, value)
    } catch (error) { this.notificationState = this.failure<NotificationView[]>(error) }
  }

  async markAllNotificationsRead(): Promise<void> {
    if (await apiClient.markAllNotificationsRead()) await this.loadNotifications()
  }

  async markNotificationRead(id: string): Promise<void> {
    if (await apiClient.markNotificationRead(id)) await this.loadNotifications()
  }

  async deleteNotification(id: string): Promise<void> {
    if (await apiClient.deleteNotification(id)) await this.loadNotifications()
  }

  async loadHome(): Promise<void> {
    this.helpState = new AsyncState<HelpArticle[]>(AsyncStatus.Loading)
    this.ticketListState = new AsyncState<SupportTicket[]>(AsyncStatus.Loading)
    await Promise.all([this.loadHelp(), this.loadTicketList()])
  }

  private async loadHelp(): Promise<void> {
    try {
      const help = await apiClient.help()
      this.helpState = help.length === 0
        ? new AsyncState<HelpArticle[]>(AsyncStatus.Empty)
        : new AsyncState<HelpArticle[]>(AsyncStatus.Success, help)
    } catch (error) {
      this.helpState = this.failure<HelpArticle[]>(error)
    }
  }

  private async loadTicketList(): Promise<void> {
    try {
      const tickets = await apiClient.tickets()
      this.ticketListState = tickets.length === 0
        ? new AsyncState<SupportTicket[]>(AsyncStatus.Empty)
        : new AsyncState<SupportTicket[]>(AsyncStatus.Success, tickets)
    } catch (error) {
      this.ticketListState = this.failure<SupportTicket[]>(error)
    }
  }

  async openTicket(id: string): Promise<void> {
    this.ticketDetailState = new AsyncState<SupportTicketDetail>(AsyncStatus.Loading)
    try {
      this.ticketDetailState = new AsyncState<SupportTicketDetail>(
        AsyncStatus.Success, await apiClient.ticket(id))
    } catch (error) {
      this.ticketDetailState = this.failure<SupportTicketDetail>(error)
    }
  }

  // Optimistically appends a freshly sent message to the open ticket detail.
  appendReply(message: SupportMessage): void {
    const detail = this.ticketDetailState.data
    if (detail === undefined) return
    const updated: SupportTicketDetail = {
      id: detail.id, category: detail.category, severity: detail.severity,
      subject: detail.subject, status: detail.status, locale: detail.locale,
      market: detail.market, dataRegion: detail.dataRegion, queueId: detail.queueId,
      createdAt: detail.createdAt, updatedAt: message.createdAt,
      messages: [...detail.messages, message]
    }
    this.ticketDetailState = new AsyncState<SupportTicketDetail>(AsyncStatus.Success, updated)
  }

  private failure<T>(error: Error): AsyncState<T> {
    if (error instanceof ApiFailure) {
      if (error.status === 401) return new AsyncState<T>(AsyncStatus.Unauthorized)
      return new AsyncState<T>(AsyncStatus.Error, undefined, error.message)
    }
    return new AsyncState<T>(AsyncStatus.Offline)
  }
}
