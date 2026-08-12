// 官方资源 i18n：文案在 AppScope/resources/{base,en_US,...}/element/string.json。
// appString() 用 resourceManager 读资源，系统/应用按语言自动匹配限定词目录。
import common from '@ohos.app.ability.common'

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
  TranslationDisplay,
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
  SaveProfile,
  // 极客译读 阅读器
  GeekReaderTitle,
  TopStories,
  LatestStories,
  RefreshSuccess,
  RefreshFail,
  LoadFailed,
  NoContent,
  NoMore,
  LoadingMore,
  OriginalText,
  Translated,
  TranslationFailed,
  BackendHint,
  Retry,
  NotLoggedIn,
  Login,
  Article,
  PointsComments,
  Comments,
  ReadOriginal,
  Deleted
}

let context: common.UIAbilityContext | null = null

export function initAppStrings(ctx: common.UIAbilityContext): void {
  context = ctx
}

// 枚举 → 资源名（语义化，与 string.json 的 name 对应）。
function resName(key: AppString): string {
  switch (key) {
    case AppString.Back: return 'back'
    case AppString.ProfileTitle: return 'profile_title'
    case AppString.SignInPrompt: return 'sign_in_prompt'
    case AppString.SignInDescription: return 'sign_in_description'
    case AppString.SignInAction: return 'sign_in_action'
    case AppString.ProfileEdit: return 'profile_edit'
    case AppString.Membership: return 'membership'
    case AppString.Statistics: return 'statistics'
    case AppString.Orders: return 'orders'
    case AppString.Settings: return 'settings'
    case AppString.SignOut: return 'sign_out'
    case AppString.AccountServices: return 'account_services'
    case AppString.Preferences: return 'preferences'
    case AppString.PrivacyStorageSupport: return 'privacy_storage_support'
    case AppString.AccountSecurity: return 'account_security'
    case AppString.Devices: return 'devices'
    case AppString.NotificationSettings: return 'notification_settings'
    case AppString.General: return 'general'
    case AppString.Appearance: return 'appearance'
    case AppString.Language: return 'language'
    case AppString.TextSize: return 'text_size'
    case AppString.TranslationDisplay: return 'translation_display'
    case AppString.Privacy: return 'privacy'
    case AppString.Permissions: return 'permissions'
    case AppString.Storage: return 'storage'
    case AppString.HelpFeedback: return 'help_feedback'
    case AppString.Legal: return 'legal'
    case AppString.About: return 'about'
    case AppString.DeleteAccount: return 'delete_account'
    case AppString.ThemeSystem: return 'theme_system'
    case AppString.ThemeLight: return 'theme_light'
    case AppString.ThemeDark: return 'theme_dark'
    case AppString.LanguageChinese: return 'language_chinese'
    case AppString.LanguageEnglish: return 'language_english'
    case AppString.TextSmall: return 'text_small'
    case AppString.TextStandard: return 'text_standard'
    case AppString.TextLarge: return 'text_large'
    case AppString.TextExtraLarge: return 'text_extra_large'
    case AppString.SaveSettings: return 'save_settings'
    case AppString.Saving: return 'saving'
    case AppString.UsernameReadonly: return 'username_readonly'
    case AppString.DisplayName: return 'display_name'
    case AppString.Bio: return 'bio'
    case AppString.ChooseAvatar: return 'choose_avatar'
    case AppString.AvatarUrl: return 'avatar_url'
    case AppString.SaveProfile: return 'save_profile'
    case AppString.GeekReaderTitle: return 'geek_reader_title'
    case AppString.TopStories: return 'top_stories'
    case AppString.LatestStories: return 'latest_stories'
    case AppString.RefreshSuccess: return 'refresh_success'
    case AppString.RefreshFail: return 'refresh_fail'
    case AppString.LoadFailed: return 'load_failed'
    case AppString.NoContent: return 'no_content'
    case AppString.NoMore: return 'no_more'
    case AppString.LoadingMore: return 'loading_more'
    case AppString.OriginalText: return 'original_text'
    case AppString.Translated: return 'translated'
    case AppString.TranslationFailed: return 'translation_failed'
    case AppString.BackendHint: return 'backend_hint'
    case AppString.Retry: return 'retry'
    case AppString.NotLoggedIn: return 'not_logged_in'
    case AppString.Login: return 'login'
    case AppString.Article: return 'article'
    case AppString.PointsComments: return 'points_comments'
    case AppString.Comments: return 'comments'
    case AppString.ReadOriginal: return 'read_original'
    case AppString.Deleted: return 'deleted'
    default: return ''
  }
}

export function appString(key: AppString, language: string): string {
  if (context !== null) {
    try {
      const name = resName(key)
      if (name.length > 0) {
        // 按资源名读当前语言（AppScope 的 app.string.*）
        const value = context.resourceManager.getStringByNameSync(name)
        if (value.length > 0) return value
      }
    } catch (e) {
      // 资源缺失时回退
    }
  }
  return resName(key)
}

export function localized(chinese: string, english: string, language: string): string {
  return language === 'en-US' ? english : chinese
}
