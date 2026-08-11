export enum AppString {
  Back,
  ProfileTitle,
  SignInPrompt,
  SignInDescription,
  SignInAction,
  ProfileEdit,
  Membership,
  Statistics,
  Orders,
  Settings,
  SignOut,
  AccountServices,
  Preferences,
  PrivacyStorageSupport,
  AccountSecurity,
  Devices,
  NotificationSettings,
  General,
  Appearance,
  Language,
  TextSize,
  Privacy,
  Permissions,
  Storage,
  HelpFeedback,
  Legal,
  About,
  DeleteAccount,
  ThemeSystem,
  ThemeLight,
  ThemeDark,
  LanguageChinese,
  LanguageEnglish,
  TextSmall,
  TextStandard,
  TextLarge,
  TextExtraLarge,
  SaveSettings,
  Saving,
  UsernameReadonly,
  DisplayName,
  Bio,
  ChooseAvatar,
  AvatarUrl,
  SaveProfile
}

const ZH: string[] = [
  '返回', '我的', '登录后同步你的数据', '会员、订单、优惠券与设置会安全同步。', '登录或注册',
  '个人资料', '会员中心', '使用统计', '订单管理', '设置', '退出登录',
  '账户与服务', '应用偏好', '隐私、存储与支持', '账户与安全', '登录设备管理',
  '通知设置', '通用设置', '外观主题', '语言', '字体大小', '隐私设置', '权限管理',
  '存储与缓存', '帮助与反馈', '协议与政策', '关于与版本', '注销账号',
  '跟随系统', '浅色', '深色', '简体中文', 'English', '较小', '标准', '较大', '特大',
  '保存设置', '保存中…', '用户名（不可修改）', '显示名称', '个人简介', '选择头像',
  '或粘贴头像 URL', '保存资料'
]

const EN: string[] = [
  'Back', 'Profile', 'Sign in to sync your data',
  'Membership, orders, coupons, and settings sync securely.', 'Sign in or create account',
  'Edit profile', 'Membership', 'Usage statistics', 'Orders', 'Settings', 'Sign out',
  'Account & services', 'App preferences', 'Privacy, storage & support',
  'Account & security', 'Signed-in devices', 'Notifications', 'General', 'Appearance',
  'Language', 'Text size', 'Privacy', 'Permissions', 'Storage & cache', 'Help & feedback',
  'Terms & policies', 'About', 'Delete account', 'Follow system', 'Light', 'Dark',
  '简体中文', 'English', 'Small', 'Standard', 'Large', 'Extra large', 'Save settings',
  'Saving…', 'Username (cannot be changed)', 'Display name', 'Bio', 'Choose avatar',
  'Or paste an avatar URL', 'Save profile'
]

export function appString(key: AppString, language: string): string {
  return (language === 'en-US' ? EN : ZH)[key]
}

export function localized(chinese: string, english: string, language: string): string {
  return language === 'en-US' ? english : chinese
}
