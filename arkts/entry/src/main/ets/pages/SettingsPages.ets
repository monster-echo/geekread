import { AppRoute, routeTitle } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppIconName } from '../design_system/AppIcon'
import { AppButton, AppListRow, PageHeader } from '../design_system/Components'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { appString, AppString } from '../localization/AppStrings'

@Component
export struct SettingsPage {
  @ObjectLink store: AppStore

  build() {
    Column() {
      PageHeader({ store: this.store, title: appString(AppString.Settings, this.store.language) })
      Scroll() {
        Column({ space: AppSpacing.x5 }) {
          SettingsGroup({
            store: this.store,
            title: appString(AppString.AccountServices, this.store.language),
            routes: this.visibleRoutes([
              AppRoute.AccountSecurity,
              AppRoute.Devices,
              AppRoute.Membership
            ])
          })
          SettingsGroup({
            store: this.store,
            title: appString(AppString.Preferences, this.store.language),
            routes: this.visibleRoutes([
              AppRoute.NotificationSettings,
              AppRoute.General,
              AppRoute.Appearance,
              AppRoute.Language,
              AppRoute.TextSize
            ])
          })
          SettingsGroup({
            store: this.store,
            title: appString(AppString.PrivacyStorageSupport, this.store.language),
            routes: this.visibleRoutes([
              AppRoute.Privacy,
              AppRoute.Permissions,
              AppRoute.Storage,
              AppRoute.HelpFeedback,
              AppRoute.PrivacyPolicy,
              AppRoute.TermsOfService,
              AppRoute.About,
              AppRoute.DeleteAccount
            ])
          })
        }
        .padding(AppSpacing.x4)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
  }

  private visibleRoutes(routes: AppRoute[]): AppRoute[] {
    return routes.filter(route => {
      if (route === AppRoute.HelpFeedback && this.store.config?.support.enabled !== true) {
        return false
      }
      const key = this.policyKey(route)
      if (key.length === 0) return true
      return this.store.config?.settingsPolicy[key]?.visibility !== 'hidden'
    })
  }

  private policyKey(route: AppRoute): string {
    if (route === AppRoute.NotificationSettings) return 'notifications'
    if (route === AppRoute.General) return 'general'
    if (route === AppRoute.Appearance || route === AppRoute.TextSize) return 'appearance'
    if (route === AppRoute.Language) return 'language'
    if (route === AppRoute.Privacy) return 'analytics'
    if (route === AppRoute.Permissions) return 'permissions'
    if (route === AppRoute.DeleteAccount) return 'accountDeletion'
    if (route === AppRoute.Membership) return 'membership'
    if (route === AppRoute.AccountSecurity) return 'accountSecurity'
    if (route === AppRoute.Devices) return 'devices'
    if (route === AppRoute.HelpFeedback) return 'helpFeedback'
    return ''
  }
}

@Component
struct SettingsGroup {
  @ObjectLink store: AppStore
  @Prop title: string
  @Prop routes: AppRoute[]

  build() {
    Column({ space: AppSpacing.x2 }) {
      Text(this.title)
        .fontSize(13)
        .fontColor(AppColors.textSecondary)
        .width('100%')
      Column() {
        ForEach(this.routes, (route: AppRoute) => {
          AppListRow({
            store: this.store,
            label: this.routeLabel(route),
            route: route
          })
        })
      }
      .backgroundColor(AppColors.surface)
      .borderRadius(AppRadii.card)
    }
  }

  private routeLabel(route: AppRoute): string {
    switch (route) {
      case AppRoute.Membership: return appString(AppString.Membership, this.store.language)
      case AppRoute.AccountSecurity: return appString(AppString.AccountSecurity, this.store.language)
      case AppRoute.Devices: return appString(AppString.Devices, this.store.language)
      case AppRoute.NotificationSettings:
        return appString(AppString.NotificationSettings, this.store.language)
      case AppRoute.General: return appString(AppString.General, this.store.language)
      case AppRoute.Appearance: return appString(AppString.Appearance, this.store.language)
      case AppRoute.Language: return appString(AppString.Language, this.store.language)
      case AppRoute.TextSize: return appString(AppString.TextSize, this.store.language)
      case AppRoute.Privacy: return appString(AppString.Privacy, this.store.language)
      case AppRoute.Permissions: return appString(AppString.Permissions, this.store.language)
      case AppRoute.Storage: return appString(AppString.Storage, this.store.language)
      case AppRoute.HelpFeedback: return appString(AppString.HelpFeedback, this.store.language)
      case AppRoute.Legal: return appString(AppString.Legal, this.store.language)
      case AppRoute.PrivacyPolicy: return '隐私条款'
      case AppRoute.TermsOfService: return '用户协议'
      case AppRoute.About: return appString(AppString.About, this.store.language)
      case AppRoute.DeleteAccount: return appString(AppString.DeleteAccount, this.store.language)
      default: return routeTitle(route)
    }
  }
}

@Component
export struct SettingDetailPage {
  @ObjectLink store: AppStore
  @Prop route: AppRoute
  @State isEnabled: boolean = true
  @State password: string = ''

  aboutToAppear(): void {
    const value = this.store.user?.settings[this.settingKey()]
    if (typeof value === 'boolean') this.isEnabled = value
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: this.title() })
      Column({ space: AppSpacing.x4 }) {
        if (this.route === AppRoute.DeleteAccount) {
          TextInput({ placeholder: '输入当前密码', text: this.password })
            .height(52)
            .type(InputType.Password)
            .backgroundColor(AppColors.surface)
            .border({ width: 1, color: AppColors.borderStrong })
            .borderRadius(AppRadii.control)
            .onChange(value => this.password = value)
        } else {
          Row() {
            Text('启用此功能').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.isEnabled })
              .selectedColor(AppColors.brand)
              .onChange(value => this.isEnabled = value)
          }
          .height(56)
          .padding({ left: AppSpacing.x4, right: AppSpacing.x4 })
          .backgroundColor(AppColors.surface)
          .borderRadius(AppRadii.card)
        }
        Text(this.route === AppRoute.DeleteAccount
          ? '账号、会话和关联业务数据将按服务端删除策略处理。'
          : '设置将立即同步到服务端，并在其他设备恢复。')
          .fontColor(AppColors.textSecondary)
        AppButton({
          label: this.route === AppRoute.DeleteAccount ? '注销账号' : '保存设置',
          icon: this.route === AppRoute.DeleteAccount
            ? AppIconName.Trash
            : AppIconName.Check,
          destructive: this.route === AppRoute.DeleteAccount,
          onTap: () => this.submit()
        })
      }
      .padding(AppSpacing.x4)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  private async submit(): Promise<void> {
    if (this.route !== AppRoute.DeleteAccount) {
      await this.store.saveSetting(this.settingKey(), this.isEnabled)
      return
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '确认注销账号？',
      message: '账号数据删除后无法恢复。',
      buttons: [
        { text: '取消', color: '#667085' },
        { text: '确认注销', color: '#D24B4B' }
      ]
    }).then(async result => {
      if (result.index === 1) {
        if (await this.store.deleteAccount(this.password)) {
          this.store.goHome()
        }
      }
    })
  }

  private settingKey(): string {
    switch (this.route) {
      case AppRoute.NotificationSettings: return 'notificationsEnabled'
      case AppRoute.Privacy: return 'analyticsEnabled'
      case AppRoute.General: return 'autoplayEnabled'
      default: return 'notificationsEnabled'
    }
  }

  private title(): string {
    if (this.route === AppRoute.NotificationSettings) {
      return appString(AppString.NotificationSettings, this.store.language)
    }
    if (this.route === AppRoute.Privacy) {
      return appString(AppString.Privacy, this.store.language)
    }
    if (this.route === AppRoute.General) {
      return appString(AppString.General, this.store.language)
    }
    if (this.route === AppRoute.DeleteAccount) {
      return appString(AppString.DeleteAccount, this.store.language)
    }
    return routeTitle(this.route)
  }
}

