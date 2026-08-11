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
      RouteHost({ store: this.store })
      if (this.store.toastMessage.length > 0) {
        ToastHost({ store: this.store })
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.background)
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

