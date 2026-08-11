export enum AppRoute {
  Logo,
  Promo,
  Onboarding,
  Home,
  SignIn,
  SignUp,
  PhoneSignIn,
  ForgotPassword,
  VerifyEmail,
  ResetPassword,
  Profile,
  ProfileEdit,
  Statistics,
  Invite,
  Coupons,
  Membership,
  MembershipPlans,
  Checkout,
  Orders,
  Settings,
  AccountSecurity,
  Devices,
  NotificationSettings,
  Privacy,
  General,
  Appearance,
  Language,
  TextSize,
  Storage,
  Permissions,
  HelpFeedback,
  Legal,
  TermsOfService,
  PrivacyPolicy,
  About,
  DeleteAccount,
  NotificationCenter,
  StateGallery,
  SupportTicket,
  NewSupportTicket,
  ProductFeedback
}

export function routeTitle(route: AppRoute): string {
  switch (route) {
    case AppRoute.ProfileEdit: return '个人资料'
    case AppRoute.Statistics: return '使用统计'
    case AppRoute.Invite: return '邀请好友'
    case AppRoute.Coupons: return '优惠券'
    case AppRoute.MembershipPlans: return '方案对比'
    case AppRoute.Checkout: return '订阅确认'
    case AppRoute.Orders: return '订单管理'
    case AppRoute.AccountSecurity: return '账户与安全'
    case AppRoute.Devices: return '登录设备管理'
    case AppRoute.NotificationSettings: return '通知设置'
    case AppRoute.Privacy: return '隐私设置'
    case AppRoute.General: return '通用设置'
    case AppRoute.Appearance: return '外观主题'
    case AppRoute.Language: return '语言'
    case AppRoute.TextSize: return '字体大小'
    case AppRoute.Storage: return '存储与缓存'
    case AppRoute.Permissions: return '权限管理'
    case AppRoute.HelpFeedback: return '帮助与反馈'
    case AppRoute.Legal: return '协议与政策'
    case AppRoute.TermsOfService: return '用户协议'
    case AppRoute.PrivacyPolicy: return '隐私政策'
    case AppRoute.About: return '关于与版本'
    case AppRoute.NotificationCenter: return '通知中心'
    case AppRoute.StateGallery: return '状态库'
    case AppRoute.SupportTicket: return '工单详情'
    case AppRoute.NewSupportTicket: return '联系客服'
    case AppRoute.ProductFeedback: return '产品反馈'
    default: return '功能页面'
  }
}
