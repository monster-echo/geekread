import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { AppIcon, AppIconName } from './AppIcon'
import { appString, AppString } from '../localization/AppStrings'

@Component
export struct AppIconButton {
  @Prop label: string
  @Prop icon: AppIconName
  onTap: () => void = () => {}

  build() {
    Button({ type: ButtonType.Normal }) {
      AppIcon({ name: this.icon })
    }
    .width(48)
    .height(48)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.label)
    .onClick(this.onTap)
  }
}

@Component
export struct AppButton {
  @Prop label: string
  icon?: AppIconName
  @Prop destructive: boolean = false
  onTap: () => void = () => {}

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: AppSpacing.x2 }) {
        if (this.icon !== undefined) {
          AppIcon({
            name: this.icon,
            color: AppColors.onBrand,
            iconSize: 20
          })
        }
        Text(this.label).fontColor(AppColors.onBrand).fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .height(52)
    .borderRadius(AppRadii.control)
    .backgroundColor(this.destructive ? AppColors.error : AppColors.brand)
    .onClick(this.onTap)
  }
}

@Component
export struct PageHeader {
  @ObjectLink store: AppStore
  @Prop title: string

  // 统一用 NavDestination 系统标题栏：此处不再自绘标题栏（避免重复）。
  // 各壳页作为 NavDestination 由 Index 的 RouteDest 提供 .title()。
  build() {
    Row() {
      // 空标题栏占位（NavDestination 系统标题栏替代）
    }.height(0).width('100%')
  }
}

@Component
export struct AppListRow {
  @ObjectLink store: AppStore
  @Prop label: string
  @Prop value: string = ''
  route?: AppRoute
  icon?: AppIconName

  build() {
    Row({ space: AppSpacing.x3 }) {
      if (this.icon !== undefined) {
        AppIcon({
          name: this.icon,
          iconSize: 20,
          color: AppColors.textSecondary
        })
      }
      Text(this.label).fontSize(16).fontColor(AppColors.text).layoutWeight(1)
      if (this.value.length > 0) {
        Text(this.value).fontSize(14).fontColor(AppColors.textSecondary)
      }
      if (this.route !== undefined) {
        AppIcon({
          name: AppIconName.ChevronRight,
          iconSize: 18,
          color: AppColors.textSecondary
        })
      }
    }
    .height(56)
    .padding({ left: AppSpacing.x4, right: AppSpacing.x4 })
    .border({ width: { bottom: 1 }, color: AppColors.border })
    .onClick(() => {
      if (this.route !== undefined) {
        this.store.navigate(this.route)
      }
    })
  }
}

