import { AppColors } from '../theme/AppTokens'

export enum AppIconName {
  Alert,
  ArrowLeft,
  Bell,
  Check,
  ChevronRight,
  Close,
  Crown,
  Gift,
  Globe,
  Home,
  Lock,
  Palette,
  Settings,
  Trash,
  User
}

function iconResource(name: AppIconName): Resource {
  switch (name) {
    case AppIconName.Alert: return $r('app.media.alert')
    case AppIconName.ArrowLeft: return $r('app.media.arrow_left')
    case AppIconName.Bell: return $r('app.media.bell')
    case AppIconName.Check: return $r('app.media.check')
    case AppIconName.ChevronRight: return $r('app.media.chevron_right')
    case AppIconName.Close: return $r('app.media.close')
    case AppIconName.Crown: return $r('app.media.crown')
    case AppIconName.Gift: return $r('app.media.gift')
    case AppIconName.Globe: return $r('app.media.globe')
    case AppIconName.Home: return $r('app.media.home')
    case AppIconName.Lock: return $r('app.media.lock')
    case AppIconName.Palette: return $r('app.media.palette')
    case AppIconName.Settings: return $r('app.media.settings')
    case AppIconName.Trash: return $r('app.media.trash')
    case AppIconName.User: return $r('app.media.user')
  }
}

@Component
export struct AppIcon {
  @Prop name: AppIconName
  @Prop iconSize: number = 24
  @Prop color: ResourceColor = AppColors.text

  build() {
    Image(iconResource(this.name))
      .width(this.iconSize)
      .height(this.iconSize)
      .fillColor(this.color)
      .objectFit(ImageFit.Contain)
  }
}
