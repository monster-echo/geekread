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
  @Prop displayMode: string = 'both' // 'original' | 'translation' | 'both'
  @State result: string = ''
  @State loading: boolean = false
  @State failed: boolean = false
  @State failedMsg: string = ''

  private get lang(): TargetLanguage | null {
    return deriveTargetLanguage(this.locale && this.locale.length > 0 ? this.locale : 'zh-CN')
  }

  aboutToAppear(): void {
    // 需要译文（translation / both）时自动触发，不点击。
    if (this.displayMode !== 'original' && this.lang !== null && this.result.length === 0) {
      this.doTranslate()
    }
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
          this.failedMsg = '译文为空'
          this.failed = true
        }
        this.loading = false
      })
      .catch((e: object) => {
        this.failedMsg = e instanceof Error ? e.message : String(e)
        this.failed = true
        this.loading = false
      })
  }

  private showOriginal(): boolean {
    return this.displayMode === 'original' || this.displayMode === 'both'
  }

  private showTranslation(): boolean {
    return this.displayMode === 'translation' || this.displayMode === 'both'
  }

  build() {
    Column({ space: AppSpacing.x1 }) {
      // 原文（original / both）
      if (this.showOriginal()) {
        Text(this.text)
          .fontSize(15)
          .fontColor(AppColors.text)
          .width('100%')
      }
      if (this.lang === null) {
        // 源语言（en 等）不译，只显原文
      } else if (this.showTranslation()) {
        if (this.displayMode === 'translation') {
          // 只看译文：先显示原文（加载中），翻译完成后原地替换成译文。
          if (this.result.length > 0) {
            Text(this.result).fontSize(14).fontColor(AppColors.text).width('100%')
          } else if (this.loading) {
            Text(this.text).fontSize(15).fontColor(AppColors.textSecondary).opacity(0.7).width('100%')
          } else if (this.failed) {
            Text(`翻译失败：${this.failedMsg}`).fontSize(11).fontColor(AppColors.textSecondary)
          } else {
            Text(this.text).fontSize(15).fontColor(AppColors.text).width('100%')
          }
        } else {
          // 双语（both）：原文已在上方，下方显示译文。
          if (this.loading) {
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
            Text(`翻译失败：${this.failedMsg}`).fontSize(11).fontColor(AppColors.textSecondary)
          }
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
