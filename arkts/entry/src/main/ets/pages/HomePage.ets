import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppIcon, AppIconName } from '../design_system/AppIcon'
import { AppIconButton } from '../design_system/Components'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { localized } from '../localization/AppStrings'

@Component
export struct HomePage {
  @ObjectLink store: AppStore

  build() {
    Column() {
      Row() {
        Column() {
          Text(localized('下午好', 'Good afternoon', this.store.language))
            .fontSize(13).fontColor(AppColors.textSecondary)
          Text(`${localized('欢迎使用', 'Welcome to', this.store.language)} ` +
            `${this.store.config?.brand.appName ?? 'MobileUI'}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.store.config?.features['notifications'] === true) {
          AppIconButton({
            label: localized('通知中心', 'Notifications', this.store.language),
            icon: AppIconName.Bell,
            onTap: () => this.store.navigate(AppRoute.NotificationCenter)
          })
        }
      }
      .height(72)
      .padding({ left: AppSpacing.x4, right: AppSpacing.x4 })
      Scroll() {
        Column({ space: AppSpacing.x5 }) {
          Row() {
            Column({ space: AppSpacing.x2 }) {
              Text(localized('会员限时体验', 'Limited membership trial', this.store.language))
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.onBrand)
              Text(localized('解锁高级功能与专属权益',
                'Unlock advanced features and benefits', this.store.language))
                .fontColor(AppColors.onBrand)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            AppIcon({
              name: AppIconName.Gift,
              color: AppColors.onBrand,
              iconSize: 42
            })
          }
          .padding(AppSpacing.x5)
          .backgroundColor(AppColors.brand)
          .borderRadius(AppRadii.card)
          .onClick(() => this.store.navigate(AppRoute.Membership))
          QuickActions({ store: this.store })
          Text(localized('最近动态', 'Recent activity', this.store.language))
            .fontSize(20).fontWeight(FontWeight.Bold).width('100%')
          Column({ space: AppSpacing.x2 }) {
            Text(localized('模板已准备完成', 'Your template is ready', this.store.language))
              .fontSize(18).fontWeight(FontWeight.Bold)
            Text(localized('三端共享页面、状态、路由与设计令牌。',
              'Shared pages, state, routes, and design tokens across platforms.',
              this.store.language))
              .fontColor(AppColors.textSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(AppSpacing.x4)
          .backgroundColor(AppColors.surface)
          .borderRadius(AppRadii.card)
          Row({ space: AppSpacing.x3 }) {
            AppIcon({
              name: AppIconName.Alert,
              color: AppColors.brand,
              iconSize: 20
            })
            Column({ space: AppSpacing.x1 }) {
              Text(localized('检查全部状态', 'Review all states', this.store.language))
                .fontWeight(FontWeight.Bold)
              Text(localized('加载、空数据、错误、离线与未授权',
                'Loading, empty, error, offline, and unauthorized', this.store.language))
                .fontSize(13)
                .fontColor(AppColors.textSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            AppIcon({
              name: AppIconName.ChevronRight,
              color: AppColors.textSecondary,
              iconSize: 18
            })
          }
          .padding(AppSpacing.x4)
          .backgroundColor(AppColors.surface)
          .borderRadius(AppRadii.card)
          .onClick(() => this.store.navigate(AppRoute.StateGallery))
        }
        .padding(AppSpacing.x4)
      }
      .layoutWeight(1)
      BottomTabs({ store: this.store, selected: AppRoute.Home })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct QuickActions {
  @ObjectLink store: AppStore

  build() {
    Row() {
      QuickAction({
        store: this.store,
        label: localized('会员', 'Membership', this.store.language),
        icon: AppIconName.Crown,
        route: AppRoute.Membership
      })
      if (this.store.config?.features['coupons'] === true) {
        QuickAction({
          store: this.store,
          label: localized('优惠券', 'Coupons', this.store.language),
          icon: AppIconName.Gift,
          route: AppRoute.Coupons
        })
      }
      if (this.store.config?.features['notifications'] === true) {
        QuickAction({
          store: this.store,
          label: localized('通知', 'Notifications', this.store.language),
          icon: AppIconName.Bell,
          route: AppRoute.NotificationCenter
        })
      }
      QuickAction({
        store: this.store,
        label: localized('设置', 'Settings', this.store.language),
        icon: AppIconName.Settings,
        route: AppRoute.Settings
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }
}

@Component
struct QuickAction {
  @ObjectLink store: AppStore
  @Prop label: string
  @Prop icon: AppIconName
  @Prop route: AppRoute

  build() {
    Column({ space: AppSpacing.x2 }) {
      Stack() {
        Rect()
          .width(52)
          .height(52)
          .radius(AppRadii.control)
          .fill(AppColors.brandSoft)
        AppIcon({ name: this.icon, color: AppColors.brand })
      }
      Text(this.label).fontSize(14)
    }
    .onClick(() => this.store.navigate(this.route))
  }
}

@Component
export struct BottomTabs {
  @ObjectLink store: AppStore
  @Prop selected: AppRoute

  build() {
    Row() {
      TabItem({ label: localized('首页', 'Home', this.store.language),
        icon: AppIconName.Home, active: this.selected === AppRoute.Home,
        onTap: () => this.store.replaceAll(AppRoute.Home) })
      TabItem({
        label: localized('会员', 'Membership', this.store.language),
        icon: AppIconName.Crown,
        active: this.selected === AppRoute.Membership,
        onTap: () => this.store.replaceAll(AppRoute.Membership)
      })
      TabItem({
        label: localized('我的', 'Profile', this.store.language),
        icon: AppIconName.User,
        active: this.selected === AppRoute.Profile,
        onTap: () => this.store.replaceAll(AppRoute.Profile)
      })
    }
    .height(66)
    .backgroundColor(AppColors.surface)
    .border({ width: { top: 1 }, color: AppColors.border })
  }
}

@Component
struct TabItem {
  @Prop label: string
  @Prop icon: AppIconName
  @Prop active: boolean = false
  onTap: () => void = () => {}

  build() {
    Column({ space: AppSpacing.x1 }) {
      AppIcon({
        name: this.icon,
        color: this.active ? AppColors.brand : AppColors.textSecondary,
        iconSize: 22
      })
      Text(this.label)
        .fontSize(12)
        .fontColor(this.active ? AppColors.brand : AppColors.textSecondary)
    }
    .layoutWeight(1)
    .onClick(this.onTap)
  }
}

