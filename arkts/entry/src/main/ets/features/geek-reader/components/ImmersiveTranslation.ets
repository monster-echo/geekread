import { AppColors, AppSpacing } from '../../../theme/AppTokens'
import { appString, AppString } from '../../../localization/AppStrings'
import { deriveTargetLanguage } from '../application/Locale'
import { translate } from '../application/TranslationCache'
import { TargetLanguage } from '../domain/Models'
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'
import { telemetry } from '../../../telemetry/Telemetry'

/** 只解码 HTML 实体（&#2f; &amp; &lt; 等），保留标签。 */
function decodeEntities(html: string): string {
  return html
    .replace(/&#x([0-9a-fA-F]+);/g, (m: string, h: string) => String.fromCharCode(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (m: string, n: string) => String.fromCharCode(Number(n)))
    .replace(/&#([0-9a-fA-F]+);/g, (m: string, h: string) => String.fromCharCode(parseInt(h, 16)))
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'").replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ')
    .replace(/&hellip;/g, '…').replace(/&mdash;/g, '—').replace(/&ndash;/g, '–')
    .replace(/&copy;/g, '©').replace(/&reg;/g, '®').replace(/&trade;/g, '™')
    .replace(/&amp;/g, '&')
}

/** 手写 HTML → Markdown（覆盖 HN 标签：p/a/i/b/code/pre/blockquote/li）。 */
function htmlToMarkdown(html: string): string {
  let s = decodeEntities(html)
  s = s.replace(/<a\s+[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, '[$2]($1)')
  s = s.replace(/<pre[^>]*>[\s\S]*?<code[^>]*>([\s\S]*?)<\/code>[\s\S]*?<\/pre>/gi, '\n```\n$1\n```\n')
  s = s.replace(/<pre[^>]*>([\s\S]*?)<\/pre>/gi, '\n```\n$1\n```\n')
  s = s.replace(/<code[^>]*>([\s\S]*?)<\/code>/gi, '`$1`')
  s = s.replace(/<strong[^>]*>([\s\S]*?)<\/strong>/gi, '**$1**')
  s = s.replace(/<b[^>]*>([\s\S]*?)<\/b>/gi, '**$1**')
  s = s.replace(/<em[^>]*>([\s\S]*?)<\/em>/gi, '*$1*')
  s = s.replace(/<i[^>]*>([\s\S]*?)<\/i>/gi, '*$1*')
  s = s.replace(/<blockquote[^>]*>([\s\S]*?)<\/blockquote>/gi, '\n> $1\n')
  s = s.replace(/<li[^>]*>([\s\S]*?)<\/li>/gi, '\n- $1')
  s = s.replace(/<\/?ul[^>]*>|<\/?ol[^>]*>/gi, '')
  s = s.replace(/<h([1-6])[^>]*>([\s\S]*?)<\/h\1>/gi, (m: string, n: string, t: string) =>
    `${'#'.repeat(Number(n))} ${t}`)
  s = s.replace(/<br\s*\/?>/gi, '\n')
  s = s.replace(/<hr\s*\/?>/gi, '\n---\n')
  s = s.replace(/<\/p>/gi, '\n\n')
  s = s.replace(/<p[^>]*>/gi, '\n\n')
  s = s.replace(/<\/div>|<\/td>|<\/tr>/gi, '\n')
  s = s.replace(/<[^>]+>/g, '')
  s = s.replace(/[ \t]+\n/g, '\n')
  s = s.replace(/\n{3,}/g, '\n\n')
  return s.trim()
}

/** 把 HTML 转成纯文本（翻译用）：解码实体、去标签、段落换行。 */
export function htmlToText(html: string): string {
  let s = decodeEntities(html)
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>|<\/div>|<\/li>|<\/h[1-6]>|<\/pre>|<\/blockquote>|<hr\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
  return s
}

@Component
export struct ImmersiveTranslation {
  @Prop text: string
  @Prop locale: string
  @Prop displayMode: string = 'both' // 'original' | 'translation' | 'both'
  @Prop free: boolean = false // true=免费通道（不扣配额）：列表标题/详情正文
  // 评论翻译的所属 topic（story）。带上后服务端按 topic 计配额：同一篇内滚动翻译只扣 1 次
  @Prop topicId: number = 0
  // true=markdown 富文本（Markdown，正文/评论）；false=纯文本 Text（标题，dark 下清晰）
  @Prop rich: boolean = true
  @State result: string = ''
  @State loading: boolean = false
  @State failed: boolean = false
  @State failedMsg: string = ''
  @State isQuota: boolean = false
  private mdController: MarkdownController = new MarkdownController()
  // HTML→Markdown / HTML→Text 结果缓存：build() 每次重渲染（loading/result 状态翻转）
  // 都会调用 markdown()/clean()，不缓存则同一段文本反复跑十几条正则（30 条评论批量挂载时
  // 放大 30×2 次）。以源文本比对做失效，text 变化（刷新复用组件）时重算。
  private mdSrc: string = ''
  private mdCache: string = ''
  private cleanSrc: string = ''
  private cleanCache: string = ''

  // 注意：struct 不支持 get 访问器（编译产物会静默丢弃，运行时读出 undefined），
  // 计算属性必须用普通方法。参考华为 FAQ「自定义组件 struct 内不支持 get/set」。
  private langOf(): TargetLanguage | null {
    return deriveTargetLanguage(this.locale && this.locale.length > 0 ? this.locale : 'zh-CN')
  }

  aboutToAppear(): void {
    // 深色模式适配：库默认文字色写死暗色，用 $r 资源（base/dark 自动切换）覆盖
    try {
      this.mdController
        .setTextColor(AppColors.text)
        .setTitleColor(AppColors.text)
        .setQuoteTextColor(AppColors.textSecondary)
        .setQuoteBorderColor(AppColors.brand)
        .setQuoteBackgroundColor(AppColors.surfaceMuted)
        .setHyperlinkTextColor(AppColors.brand)
        .setInlineCodeColor(AppColors.text)
        .setInlineCodeBackgroundColor(AppColors.surfaceMuted)
        .setUlPointColor(AppColors.text)
        .setLineColor(AppColors.border)
        // 可见区域懒渲染（3.4.2+，默认关闭）：屏外块先渲染轻量占位，进入可见区附近
        // 再渲真实内容。整树同步渲染（IntactRender）曾把主线程占满数秒触发 APP_FREEZE
        // 冻屏；外层是 Scroll 容器，满足懒渲染触发条件（未开文本选择，无回退问题）。
        .setLazyRender(true)
        .setLazyPreloadBlockCount(3)
    } catch (e) {
      // 库未就绪时静默降级（富文本用默认样式）
    }
    // 需要译文（translation / both）时自动触发，不点击。清洗后为空的文本不触发
    // （链接/图片型评论没有可译内容，避免空转圈）。
    if (this.displayMode !== 'original' && this.langOf() !== null &&
      this.result.length === 0 && this.clean().trim().length > 0) {
      this.doTranslate()
    }
  }

  private doTranslate(): void {
    const l = this.langOf()
    if (l === null) return
    this.loading = true
    this.failed = false
    translate(this.clean(), l, this.free, this.topicId)
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
        const msg = e instanceof Error ? e.message : String(e)
        if (msg === 'quota_exceeded') {
          this.isQuota = true
        } else {
          telemetry.report(new Error(`translate_failed: ${msg}`))
        }
        this.failedMsg = msg
        this.failed = true
        this.loading = false
      })
  }

  private markdown(): string {
    if (this.mdSrc !== this.text) {
      this.mdSrc = this.text
      this.mdCache = htmlToMarkdown(this.text)
    }
    return this.mdCache
  }

  private clean(): string {
    if (this.cleanSrc !== this.text) {
      this.cleanSrc = this.text
      this.cleanCache = htmlToText(this.text)
    }
    return this.cleanCache
  }

  private showOriginal(): boolean {
    return this.displayMode === 'original' || this.displayMode === 'both'
  }

  private showTranslation(): boolean {
    return this.displayMode === 'translation' || this.displayMode === 'both'
  }

  build() {
    Column({ space: AppSpacing.x1 }) {
      // 原文（original / both）：rich=true 用 Markdown 富文本（正文/评论）；
      // rich=false 用纯文本 Text（标题，dark 下清晰）。
      if (this.showOriginal()) {
        if (this.rich) {
          Markdown({ controller: this.mdController, text: this.markdown() })
        } else {
          Text(this.clean())
            .fontSize(15)
            .fontColor(AppColors.text)
            .width('100%')
        }
      }
      if (this.langOf() === null) {
        // 源语言（en 等）不译，只显原文
      } else if (this.showTranslation()) {
        if (this.displayMode === 'translation') {
          // 只看译文：先显示原文（加载中），翻译完成后原地替换成译文；
          // 失败时保留原文，下方显示失败提示。
          if (this.result.length > 0) {
            // 《人工智能生成合成内容标识办法》显式标识：文字须同时含"AI"+"生成"两要素
            Column({ space: AppSpacing.x1 }) {
              Text(appString(AppString.AIGeneratedTranslation, this.locale))
                .fontSize(11)
                .fontColor(AppColors.brand)
              Text(this.result).fontSize(14).letterSpacing(0.8).fontColor(AppColors.text).width('100%')
            }.alignItems(HorizontalAlign.Start).width('100%')
          } else {
            Column({ space: AppSpacing.x1 }) {
              if (this.rich) {
                Markdown({ controller: this.mdController, text: this.markdown() })
              } else {
                Text(this.clean()).fontSize(15).fontColor(AppColors.text).width('100%')
              }
              if (this.loading) {
                LoadingProgress().width(18).height(18)
              } else if (this.failed) {
                if (this.isQuota) {
                  Text('今日免费话题已用完 · 升级 Pro 可继续')
                    .fontSize(11).fontColor(AppColors.brand).fontWeight(FontWeight.Bold)
                } else {
                  Text(`翻译失败：${this.failedMsg}`).fontSize(11).fontColor(AppColors.textSecondary)
                }
              }
            }.alignItems(HorizontalAlign.Start).width('100%')
          }
        } else {
          // 双语（both）：原文已在上方，下方显示译文。
          if (this.loading) {
            LoadingProgress().width(20).height(20)
          } else if (this.result.length > 0) {
            Column({ space: AppSpacing.x1 }) {
              // 合规显式标识：文字须同时含"AI"+"生成"两要素，不能只写"译"
              Text(appString(AppString.AIGeneratedTranslation, this.locale))
                .fontSize(11)
                .fontColor(AppColors.brand)
              Text(this.result)
                .fontSize(14)
                .letterSpacing(0.8)
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
