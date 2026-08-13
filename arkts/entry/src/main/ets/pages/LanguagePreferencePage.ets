import { AppStore } from '../state/AppStore'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { AppButton, PageHeader } from '../design_system/Components'
import { AppIconName } from '../design_system/AppIcon'
import { appString, AppString } from '../localization/AppStrings'

const LANGUAGES: string[] = [
  'zh-CN', 'zh-TW', 'en-US', 'ms-MY', 'id-ID', 'th-TH', 'vi-VN', 'ar-SA', 'ja-JP', 'ko-KR',
]
const DISPLAY_MODES: string[] = ['original', 'both', 'translation']

function languageLabel(code: string): string {
  if (code === 'zh-CN') return '简体中文'
  if (code === 'zh-TW') return '繁體中文'
  if (code === 'en-US') return 'English'
  if (code === 'ms-MY') return 'Bahasa Melayu'
  if (code === 'id-ID') return 'Bahasa Indonesia'
  if (code === 'th-TH') return 'ไทย'
  if (code === 'vi-VN') return 'Tiếng Việt'
  if (code === 'ar-SA') return 'العربية'
  if (code === 'ja-JP') return '日本語'
  if (code === 'ko-KR') return '한국어'
  return code
}

function displayLabel(mode: string, language: string): string {
  if (mode === 'original') return appString(AppString.DisplayOriginal, language)
  if (mode === 'both') return appString(AppString.DisplayBoth, language)
  if (mode === 'translation') return appString(AppString.DisplayTranslation, language)
  return mode
}

@Component
export struct LanguagePreferencePage {
  @ObjectLink store: AppStore
  @State language: string = 'zh-CN'
  @State displayMode: string = 'both'

  aboutToAppear(): void {
    this.language = this.store.language
    this.displayMode = this.store.translationDisplayMode
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: appString(AppString.Language, this.store.language) })
      Scroll() {
        Column({ space: AppSpacing.x5 }) {
          // 界面语言
          Column({ space: AppSpacing.x2 }) {
            Text(appString(AppString.InterfaceLanguage, this.store.language))
              .fontSize(13).fontColor(AppColors.textSecondary).width('100%')
            Column() {
              ForEach(LANGUAGES, (code: string) => {
                Row({ space: AppSpacing.x3 }) {
                  Radio({ group: 'lang', value: code }).checked(this.language === code)
                    .onChange((isChecked: boolean) => { console.log('[radio] lang onChange', code, isChecked); if (isChecked) this.language = code })
                  Text(languageLabel(code))
                    .fontSize(16).fontColor(AppColors.text).layoutWeight(1)
                    .onClick(() => { console.log('[radio] lang onClick', code); this.language = code })
                }
                .width('100%').height(52).padding({ left: AppSpacing.x4, right: AppSpacing.x4 })
                .backgroundColor(AppColors.surface)
                .onClick(() => { console.log('[radio] row onClick', code); this.language = code })
              })
            }.backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
          }.alignItems(HorizontalAlign.Start).width('100%')

          // 翻译显示模式
          Column({ space: AppSpacing.x2 }) {
            Text(appString(AppString.TranslationDisplay, this.store.language))
              .fontSize(13).fontColor(AppColors.textSecondary).width('100%')
            Column() {
              ForEach(DISPLAY_MODES, (mode: string) => {
                Row({ space: AppSpacing.x3 }) {
                  Radio({ group: 'display', value: mode }).checked(this.displayMode === mode)
                    .onChange((isChecked: boolean) => { console.log('[radio] display onChange', mode, isChecked); if (isChecked) this.displayMode = mode })
                  Text(displayLabel(mode, this.store.language))
                    .fontSize(16).fontColor(AppColors.text).layoutWeight(1)
                    .onClick(() => { console.log('[radio] display onClick', mode); this.displayMode = mode })
                }
                .width('100%').height(52).padding({ left: AppSpacing.x4, right: AppSpacing.x4 })
                .backgroundColor(AppColors.surface)
                .onClick(() => { console.log('[radio] display row onClick', mode); this.displayMode = mode })
              })
            }.backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
          }.alignItems(HorizontalAlign.Start).width('100%')

          AppButton({
            label: this.store.busy
              ? appString(AppString.Saving, this.store.language)
              : appString(AppString.SaveSettings, this.store.language),
            icon: AppIconName.Check,
            onTap: () => this.save()
          })
        }.padding(AppSpacing.x4).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1)
    }.width('100%').height('100%')
  }

  private async save(): Promise<void> {
    console.log(`[radio] save language=${this.language} displayMode=${this.displayMode}`)
    await this.store.saveSetting('language', this.language)
    await this.store.saveSetting('translationDisplay', this.displayMode)
  }
}
