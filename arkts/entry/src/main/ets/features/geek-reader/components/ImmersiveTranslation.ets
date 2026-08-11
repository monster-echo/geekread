import { AppColors, AppSpacing } from '../../../theme/AppTokens'
import { deriveTargetLanguage } from '../application/Locale'
import { translate } from '../application/TranslationCache'
import { TargetLanguage } from '../domain/Models'

const LANG_LABEL: Record<TargetLanguage, string> = {
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
}

@Component
export struct ImmersiveTranslation {
  @Prop text: string
  @Prop locale: string
  @State result: string = ''
  @State loading: boolean = false
  @State failed: boolean = false
  @State armed: boolean = false

  private get lang(): TargetLanguage | null {
    return deriveTargetLanguage(this.locale)
  }

  private get langLabel(): string {
    const l = this.lang
    return l === null ? '' : LANG_LABEL[l]
  }

  private doTranslate(): void {
    const l = this.lang
    if (l === null) return
    this.loading = true
    translate(this.text, l)
      .then((t: string) => { this.result = t; this.loading = false })
      .catch(() => { this.failed = true; this.loading = false })
  }

  build() {
    Column({ space: AppSpacing.x1 }) {
      Text(this.text)
        .fontSize(15)
        .fontColor(AppColors.text)
        .width('100%')
      if (this.lang === null) {
        // 源语言（en/其它）不译，只显原文。
      } else if (this.loading) {
        LoadingProgress().width(20).height(20)
      } else if (this.result.length > 0) {
        Column({ space: AppSpacing.x1 }) {
          Text(`译 · ${this.langLabel}`)
            .fontSize(11)
            .fontColor(AppColors.brand)
          Text(this.result)
            .fontSize(14)
            .fontColor(AppColors.text)
        }
        .alignItems(HorizontalAlign.Start)
        .border({ width: { left: 3 } })
        .borderColor(AppColors.brand)
        .padding({ left: AppSpacing.x2 })
        .width('100%')
      } else if (this.failed) {
        Text('翻译失败').fontSize(11).fontColor(AppColors.textSecondary)
      } else {
        Button(`译 · ${this.langLabel}`)
          .type(ButtonType.Normal)
          .backgroundColor(AppColors.brandSoft)
          .fontColor(AppColors.brand)
          .fontSize(12)
          .height(32)
          .onClick(() => this.doTranslate())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
