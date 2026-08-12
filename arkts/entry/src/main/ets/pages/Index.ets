import common from '@ohos.app.ability.common'
import { AppRoute } from '../navigation/AppRoute'
import { EntryIntent, entryIntentInbox } from '../navigation/EntryIntent'
import { AppStore } from '../state/AppStore'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { AppIcon, AppIconName } from '../design_system/AppIcon'
import { AuthMode, AuthPage } from './AuthPage'
import { StateGalleryPage } from './GenericPage'
import { CouponsPage, InvitePage, StatisticsPage } from './ProfileDataPages'
import { OrdersPage, SessionsPage } from './AccountDataPages'
import { NotificationPage } from './NotificationPage'
import {
  AboutPage, AccountSecurityPage, ChoicePreferencePage,
  LegalDocumentPage, LegalPage, ProfileEditPage
} from './SettingsActionPages'
import { HomePage } from './HomePage'
import { OnboardingPage, SplashPage } from './LaunchPages'
import { CheckoutPage } from './CheckoutPage'
import { MembershipPage, ProfilePage } from './ProfilePages'
import { SettingDetailPage, SettingsPage } from './SettingsPages'
import { SettingsUtilityPage } from './SettingsUtilityPage'
import {
  NewSupportTicketPage, ProductFeedbackPage, SupportHomePage, SupportTicketPage
} from './SupportPages'
import { GeekReaderPage } from '../features/geek-reader/pages/GeekReaderPage'
import { StoryDetailPage } from '../features/geek-reader/pages/StoryDetailPage'
import { LanguagePreferencePage } from './LanguagePreferencePage'
import { GeekMemberPage } from '../features/geek-reader/pages/GeekMemberPage'

@Entry
@Component
struct Index {
  @State store: AppStore = new AppStore()

  aboutToAppear(): void {
    this.store.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext)
    entryIntentInbox.subscribe(this)
  }

  aboutToDisappear(): void {
    entryIntentInbox.unsubscribe(this)
  }

  onEntryIntent(intent: EntryIntent): void {
    this.store.openEntryByName(intent.routeName, intent.cold)
  }

  onResume(): void {
    this.store.resume()
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Navigation(this.store.pathStack) {
        // 根内容 = 启动页：goHome 后 replaceAll(GeekReader) 清栈压入阅读器。
        SplashPage({ store: this.store })
      }
      .mode(NavigationMode.Stack)
      .navDestination(this.RouteDest)
      .hideTitleBar(true)
      .width('100%').height('100%')
      if (this.store.toastMessage.length > 0) {
        ToastHost({ store: this.store })
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.background)
  }

  @Builder
  RouteDest(name: string, param: object) {
    if (name === `route_${AppRoute.GeekReader}`) {
      NavDestination() { GeekReaderPage({ store: this.store }) }.hideTitleBar(true)
    } else if (name === `route_${AppRoute.Home}`) {
      NavDestination() { HomePage({ store: this.store }) }.hideTitleBar(true)
      NavDestination() { GeekReaderPage({ store: this.store }) }.hideTitleBar(true)
    } else if (name === `route_${AppRoute.GeekReaderDetail}`) {
      NavDestination() { StoryDetailPage({ store: this.store }) }.title('文章').hideTitleBar(false)
    } else if (name === `route_${AppRoute.Settings}`) {
      NavDestination() { SettingsPage({ store: this.store }) }.title('设置').hideTitleBar(false)
    } else if (name === `route_${AppRoute.About}`) {
      NavDestination() { AboutPage({ store: this.store }) }.title('关于与版本').hideTitleBar(false)
    } else if (name === `route_${AppRoute.Legal}`) {
      NavDestination() { LegalPage({ store: this.store }) }.title('协议与政策').hideTitleBar(false)
    } else if (name === `route_${AppRoute.PrivacyPolicy}`) {
      NavDestination() { LegalDocumentPage({ store: this.store, type: 'privacy' }) }.title('隐私政策').hideTitleBar(false)
    } else if (name === `route_${AppRoute.TermsOfService}`) {
      NavDestination() { LegalDocumentPage({ store: this.store, type: 'terms' }) }.title('用户协议').hideTitleBar(false)
    } else if (name === `route_${AppRoute.Language}`) {
      NavDestination() { LanguagePreferencePage({ store: this.store }) }.title('语言').hideTitleBar(false)
    } else if (name === `route_${AppRoute.Appearance}` || name === `route_${AppRoute.TextSize}` || name === `route_${AppRoute.TranslationDisplay}`) {
      NavDestination() { ChoicePreferencePage({ store: this.store, route: this.store.route }) }.title(this.choiceTitle()).hideTitleBar(false)
    } else if (name === `route_${AppRoute.Storage}` || name === `route_${AppRoute.Permissions}`) {
      NavDestination() { SettingsUtilityPage({ store: this.store, route: this.store.route }) }.title(this.choiceTitle()).hideTitleBar(false)
    } else if (name === `route_${AppRoute.SignIn}` || name === `route_${AppRoute.SignUp}` || name === `route_${AppRoute.PhoneSignIn}` || name === `route_${AppRoute.ForgotPassword}` || name === `route_${AppRoute.VerifyEmail}` || name === `route_${AppRoute.ResetPassword}`) {
      NavDestination() { AuthPage({ store: this.store, mode: this.authMode() }) }.title(this.authTitle()).hideTitleBar(false)
    } else if (name === `route_${AppRoute.Privacy}` || name === `route_${AppRoute.NotificationSettings}` || name === `route_${AppRoute.General}` || name === `route_${AppRoute.DeleteAccount}`) {
      // 开关类设置页（隐私/通知/通用/注销）
      NavDestination() { SettingDetailPage({ store: this.store, route: this.store.route }) }.title(this.choiceTitle()).hideTitleBar(false)
    } else if (name === `route_${AppRoute.HelpFeedback}`) {
      NavDestination() { SupportHomePage({ store: this.store, remote: this.store.remote }) }.title('帮助与反馈').hideTitleBar(false)
    } else if (name === `route_${AppRoute.SupportTicket}`) {
      NavDestination() { SupportTicketPage({ store: this.store, remote: this.store.remote }) }.title('工单详情').hideTitleBar(false)
    } else if (name === `route_${AppRoute.NewSupportTicket}`) {
      NavDestination() { NewSupportTicketPage({ store: this.store }) }.title('联系客服').hideTitleBar(false)
    } else if (name === `route_${AppRoute.ProductFeedback}`) {
      NavDestination() { ProductFeedbackPage({ store: this.store }) }.title('产品反馈').hideTitleBar(false)
    } else if (name === `route_${AppRoute.AccountSecurity}`) {
      NavDestination() { AccountSecurityPage({ store: this.store }) }.title('账户与安全').hideTitleBar(false)
    } else if (name === `route_${AppRoute.Devices}`) {
      NavDestination() { SessionsPage({ store: this.store, remote: this.store.remote }) }.title('登录设备管理').hideTitleBar(false)
    } else if (name === `route_${AppRoute.Membership}`) {
      NavDestination() { GeekMemberPage({ store: this.store }) }.title('会员中心').hideTitleBar(false)
    } else if (name === `route_${AppRoute.MembershipPlans}`) {
      NavDestination() { MembershipPage({ store: this.store }) }.title('方案对比').hideTitleBar(false)
    } else if (name === `route_${AppRoute.Checkout}`) {
      NavDestination() { CheckoutPage({ store: this.store }) }.title('订阅确认').hideTitleBar(false)
    } else if (name === `route_${AppRoute.Orders}`) {
      NavDestination() { OrdersPage({ store: this.store, remote: this.store.remote }) }.title('订单记录').hideTitleBar(false)
    } else if (name === `route_${AppRoute.Profile}`) {
      NavDestination() { ProfilePage({ store: this.store }) }.title('我的').hideTitleBar(false)
    } else {
      // 未注册的路由 → 404（不静默掉进错误的通用页）
      NavDestination() { NotFoundPage() }.title('页面不存在').hideTitleBar(false)
    }
  }

  private authMode(): AuthMode {
    if (this.store.route === AppRoute.SignUp) return AuthMode.SignUp
    if (this.store.route === AppRoute.PhoneSignIn) return AuthMode.Phone
    if (this.store.route === AppRoute.ForgotPassword) return AuthMode.Forgot
    if (this.store.route === AppRoute.VerifyEmail) return AuthMode.Verify
    if (this.store.route === AppRoute.ResetPassword) return AuthMode.Reset
    return AuthMode.SignIn
  }

  private choiceTitle(): string {
    const r = this.store.route
    if (r === AppRoute.Appearance) return '外观主题'
    if (r === AppRoute.Language) return '语言'
    if (r === AppRoute.TextSize) return '字体大小'
    if (r === AppRoute.TranslationDisplay) return '翻译显示'
    if (r === AppRoute.Storage) return '存储与缓存'
    if (r === AppRoute.Permissions) return '权限管理'
    if (r === AppRoute.Privacy) return '隐私设置'
    if (r === AppRoute.NotificationSettings) return '通知设置'
    if (r === AppRoute.General) return '通用设置'
    if (r === AppRoute.DeleteAccount) return '注销账号'
    return '设置'
  }

  private authTitle(): string {
    const r = this.store.route
    if (r === AppRoute.SignUp) return '创建账号'
    if (r === AppRoute.PhoneSignIn) return '手机号登录'
    if (r === AppRoute.ForgotPassword) return '找回密码'
    if (r === AppRoute.VerifyEmail) return '验证邮箱'
    if (r === AppRoute.ResetPassword) return '重置密码'
    return '登录'
  }
}

@Component
struct RouteHost {
  @ObjectLink store: AppStore
  build() {
    if (this.store.route <= AppRoute.ResetPassword) {
      LaunchAuthHost({ store: this.store })
    } else if (this.store.route <= AppRoute.Orders) {
      ProfileHost({ store: this.store })
    } else {
      SettingsHost({ store: this.store })
    }
  }
}

@Component
struct LaunchAuthHost {
  @ObjectLink store: AppStore
  build() {
    if (this.store.route === AppRoute.Logo) {
      SplashPage({ store: this.store })
    } else if (this.store.route === AppRoute.Promo) {
      SplashPage({ store: this.store })
    } else if (this.store.route === AppRoute.Onboarding) {
      OnboardingPage({ store: this.store })
    } else if (this.store.route === AppRoute.Home) {
      HomePage({ store: this.store })
    } else {
      AuthPage({ store: this.store, mode: this.authMode() })
    }
  }

  private authMode(): AuthMode {
    if (this.store.route === AppRoute.SignUp) return AuthMode.SignUp
    if (this.store.route === AppRoute.PhoneSignIn) return AuthMode.Phone
    if (this.store.route === AppRoute.ForgotPassword) return AuthMode.Forgot
    if (this.store.route === AppRoute.VerifyEmail) return AuthMode.Verify
    if (this.store.route === AppRoute.ResetPassword) return AuthMode.Reset
    return AuthMode.SignIn
  }
}

@Component
struct ProfileHost {
  @ObjectLink store: AppStore
  build() {
    if (this.store.route === AppRoute.Profile) {
      ProfilePage({ store: this.store })
    } else if (this.store.route === AppRoute.ProfileEdit) {
      ProfileEditPage({ store: this.store })
    } else if (this.store.route === AppRoute.Statistics) {
      StatisticsPage({ store: this.store, remote: this.store.remote })
    } else if (this.store.route === AppRoute.Invite) {
      InvitePage({ store: this.store, remote: this.store.remote })
    } else if (this.store.route === AppRoute.Coupons) {
      CouponsPage({ store: this.store, remote: this.store.remote })
    } else if (this.store.route === AppRoute.Orders) {
      OrdersPage({ store: this.store, remote: this.store.remote })
    } else if (this.store.route === AppRoute.Checkout) {
      CheckoutPage({ store: this.store })
    } else {
      MembershipPage({ store: this.store })
    }
  }
}

@Component
struct SettingsHost {
  @ObjectLink store: AppStore
  build() {
    if (this.store.route === AppRoute.Settings) {
      SettingsPage({ store: this.store })
    } else if (this.store.route === AppRoute.Devices) {
      SessionsPage({ store: this.store, remote: this.store.remote })
    } else if (this.store.route === AppRoute.NotificationCenter) {
      NotificationPage({ store: this.store, remote: this.store.remote })
    } else if (this.store.route === AppRoute.AccountSecurity) {
      AccountSecurityPage({ store: this.store })
    } else if (this.isChoiceRoute()) {
      ChoicePreferencePage({ store: this.store, route: this.store.route })
    } else if (this.store.route === AppRoute.Legal) {
      LegalPage({ store: this.store })
    } else if (this.store.route === AppRoute.TermsOfService) {
      LegalDocumentPage({ store: this.store, type: 'terms' })
    } else if (this.store.route === AppRoute.PrivacyPolicy) {
      LegalDocumentPage({ store: this.store, type: 'privacy' })
    } else if (this.store.route === AppRoute.About) {
      AboutPage({ store: this.store })
    } else if (this.store.route === AppRoute.Storage ||
      this.store.route === AppRoute.Permissions) {
      SettingsUtilityPage({ store: this.store, route: this.store.route })
    } else if (this.store.route === AppRoute.HelpFeedback) {
      SupportHomePage({ store: this.store, remote: this.store.remote })
    } else if (this.store.route === AppRoute.SupportTicket) {
      SupportTicketPage({ store: this.store, remote: this.store.remote })
    } else if (this.store.route === AppRoute.NewSupportTicket) {
      NewSupportTicketPage({ store: this.store })
    } else if (this.store.route === AppRoute.ProductFeedback) {
      ProductFeedbackPage({ store: this.store })
    } else if (this.store.route === AppRoute.StateGallery) {
      StateGalleryPage({ store: this.store })
    } else if (this.store.route === AppRoute.GeekReader) {
      GeekReaderPage({ store: this.store })
    } else if (this.store.route === AppRoute.GeekReaderDetail) {
      StoryDetailPage({ store: this.store })
    } else {
      SettingDetailPage({ store: this.store, route: this.store.route })
    }
  }

  private isChoiceRoute(): boolean {
    return this.store.route === AppRoute.Appearance ||
      this.store.route === AppRoute.Language || this.store.route === AppRoute.TextSize
  }
}

@Component
struct ToastHost {
  @ObjectLink store: AppStore
  build() {
    Row({ space: AppSpacing.x3 }) {
      AppIcon({
        name: this.store.toastError ? AppIconName.Alert : AppIconName.Check,
        color: this.store.toastError ? AppColors.error : AppColors.success,
        iconSize: 20
      })
      Text(this.store.toastMessage).fontColor(AppColors.text)
    }
    .margin(AppSpacing.x4).padding(AppSpacing.x4).width('90%')
    .backgroundColor(AppColors.surface).borderRadius(AppRadii.control)
    .shadow({ radius: 16, color: '#26000000', offsetY: 4 })
  }
}


@Component
struct NotFoundPage {
  build() {
    Column({ space: AppSpacing.x3 }) {
      Text('404')
        .fontSize(48).fontWeight(FontWeight.Bold).fontColor(AppColors.textSecondary)
      Text('页面不存在')
        .fontSize(16).fontColor(AppColors.textSecondary)
    }
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .width('100%').height('100%')
  }
}
