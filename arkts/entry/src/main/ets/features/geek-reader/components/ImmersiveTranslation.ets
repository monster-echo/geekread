import { AppColors, AppSpacing } from '../../../theme/AppTokens'
import { deriveTargetLanguage } from '../application/Locale'
import { translate } from '../application/TranslationCache'
import { TargetLanguage } from '../domain/Models'

function labelOf(lang: TargetLanguage | null): string {
  if (lang === 'zh-Hans') return '简体中文'
  if (lang === 'zh-Hant') return '繁體中文'
  if (lang === 'ja') return '日本語'
  if (lang === 'ko') return '한국어'
  if (lang === 'en') return 'English'
  return '简体中文'
}

@Component
export struct ImmersiveTranslation {
  @Prop text: string
  @Prop locale: string
  @State result: string = ''
  @State loading: boolean = false
  @State failed: boolean = false

  private get lang(): TargetLanguage | null {
    return deriveTargetLanguage(this.locale && this.locale.length > 0 ? this.locale : 'zh-CN')
  }

  private doTranslate(): void {
    const l = this.lang
    if (l === null) return
    this.loading = true
    this.failed = false
    translate(this.text, l)
      .then((t: string) => {
        if (typeof t === 'string' && t.length > 0 && t !== 'undefined') {
          this.result = t
        } else {
          this.failed = true
        }
        this.loading = false
      })
      .catch(() => { this.failed = true; this.loading = false })
  }

  build() {
    Column({ space: AppSpacing.x1 }) {
      Text(this.text)
        .fontSize(15)
        .fontColor(AppColors.text)
        .width('100%')
      if (this.lang === null) {
        // 源语言（en 等）不译，只显原文
      } else if (this.loading) {
        LoadingProgress().width(20).height(20)
      } else if (this.result.length > 0) {
        Column({ space: AppSpacing.x1 }) {
          Text(`译 · ${labelOf(this.lang)}`)
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
        Text('翻译失败（后端未配 LLM）').fontSize(11).fontColor(AppColors.textSecondary)
      } else {
        Button(`译 · ${labelOf(this.lang)}`)
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
