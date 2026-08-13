import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppButton } from '../design_system/Components'
import { AppColors, AppSpacing } from '../theme/AppTokens'
import { SplashConfig } from '../domain/Models'

// ── Splash page ──────────────────────────────────────────────────────────
// 统一三端启动体验：原生 logo → 品牌闪屏 → home。闪屏仅在「在线且有 splash 配置」
// 时展示（全屏媒体 + 右上角胶囊跳过 + 倒计时）；离线或未配置 → 直接进首页。
//
// 阶段：
//  1. loading：logo + appName + tagline + 加载指示 + "加载中…"
//     等待「最短展示 1s AND 初始 bootstrap 完成」（8s 兜底防 fetch 挂死）
//  2. bootstrap 完成后判断：splash==null 或 离线 → 直进首页；
//     在线且有 splash → 品牌闪屏（倒计时用 durationSeconds）→ home

const MIN_LOGO_DELAY_MS: number = 1000
const MAX_SPLASH_WAIT_MS: number = 8000

@Component
export struct SplashPage {
  @ObjectLink @Watch('onStoreChanged') store: AppStore
  @State minElapsed: boolean = false
  @State countdown: number = -1 // -1 = loading 阶段；>=0 = 品牌闪屏阶段
  private minTimer: number = -1
  private maxTimer: number = -1
  private countdownTimer: number = -1
  private advancing: boolean = false
  private done: boolean = false

  private get splashConfig(): SplashConfig | null {
    return this.store.config?.splash ?? null
  }

  aboutToAppear(): void {
    this.minTimer = setTimeout(() => {
      this.minElapsed = true
      this.maybeAdvance()
    }, MIN_LOGO_DELAY_MS)
    // fetch 无显式超时，最长等待兜底，避免一直卡在 loading
    this.maxTimer = setTimeout(() => this.goHome(), MAX_SPLASH_WAIT_MS)
  }

  aboutToDisappear(): void {
    if (this.minTimer !== -1) clearTimeout(this.minTimer)
    if (this.maxTimer !== -1) clearTimeout(this.maxTimer)
    if (this.countdownTimer !== -1) clearInterval(this.countdownTimer)
  }

  onStoreChanged(): void {
    this.maybeAdvance()
  }

  maybeAdvance(): void {
    if (this.advancing || this.countdown !== -1) return
    if (!this.minElapsed || !this.store.bootstrapped) return
    const splash = this.store.config?.splash ?? null
    if (splash === null || !this.store.online) {
      this.goHome() // 未配置闪屏或离线 → 直接进首页
      return
    }
    this.advancing = true
    this.enterSplash(splash)
  }

  enterSplash(splash: SplashConfig): void {
    // ArkTS 无 RN Image.prefetch 等价的简单预加载 API，依赖 Image/Video 组件自身加载；
    // loading 阶段已吸收首拉延迟，组件 onError 回退 fallback，不致黑屏。
    this.countdown = splash.durationSeconds
    this.countdownTimer = setInterval(() => {
      if (this.countdown <= 1) {
        clearInterval(this.countdownTimer)
        this.goHome()
        return
      }
      this.countdown--
    }, 1000)
  }

  goHome(): void {
    if (this.done) return
    this.done = true
    // 标记 splash 完成：根内容直接切到阅读器（GeekReader 是导航根）。
    // 不 replaceAll 压栈——否则根里一个、栈顶又一个，出现两个阅读器。
    this.store.splashDone = true
  }

  build() {
    if (this.countdown === -1) {
      // 阶段 loading：logo + appName + tagline + 加载指示 + "加载中…"
      Column({ space: AppSpacing.x3 }) {
        Image($r('app.media.app_icon')).width(48).height(48).borderRadius(12)
        Text(this.store.config?.brand.appName ?? 'MobileUI')
          .fontSize(28).fontWeight(FontWeight.Bold)
        Text(this.store.config?.brand.tagline ?? '')
          .fontColor(AppColors.textSecondary).fontSize(14)
        LoadingProgress().width(24).height(24).color(AppColors.brand)
        Text('加载中…').fontColor(AppColors.brand).fontSize(14)
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(AppColors.background)
    } else {
      // 闪屏阶段：countdown 非空即已确认有 splash 配置（maybeAdvance 保证非空）
      if (this.splashConfig != null) {
        Stack({ alignContent: Alignment.TopEnd }) {
          SplashMedia({ splash: this.splashConfig })
          Row() {
            SkipCapsule({
              countdown: Math.max(this.countdown, 0),
              canSkip: this.splashConfig.skippable !== false,
              onSkip: () => { this.goHome() }
            })
          }
          .padding(AppSpacing.x3)
        }
        .width('100%').height('100%')
        .backgroundColor(AppColors.background)
      }
    }
  }
}

// 右上角胶囊跳过按钮（开屏广告标准形态：半透明深底 + 白字 + 倒计时）
@Component
struct SkipCapsule {
  countdown: number = 0
  canSkip: boolean = true
  onSkip: () => void = () => {}

  build() {
    Text(this.canSkip ? `${this.countdown} s 跳过` : `${this.countdown} s`)
      .fontColor(Color.White).fontSize(14).fontWeight(FontWeight.Medium)
      .constraintSize({ minHeight: 36, minWidth: 72 })
      .padding({ left: AppSpacing.x3, right: AppSpacing.x3 })
      .backgroundColor('rgba(0,0,0,0.4)')
      .borderRadius(999)
      .textAlign(TextAlign.Center)
      .accessibilityText(`跳过闪屏，剩余 ${this.countdown} 秒`)
      .onClick(() => this.onSkip())
  }
}

// 全屏媒体背景：视频（videoUrl）> 图片（imageUrl cover）> 品牌 fallback。
// 视频/图片加载失败逐级回退；加载期间透出 app 背景色（父级提供），避免黑屏。
@Component
struct SplashMedia {
  @Prop splash: SplashConfig
  @State videoFailed: boolean = false
  @State imageFailed: boolean = false

  build() {
    Stack() {
      if (this.splash.videoUrl && !this.videoFailed) {
        Video({
          src: this.splash.videoUrl,
          currentProgressRate: PlaybackSpeed.Speed_Forward_1_00_X
        })
          .autoPlay(true).loop(true).muted(true)
          .objectFit(ImageFit.Cover).controls(false)
          .width('100%').height('100%')
          .onError(() => { this.videoFailed = true })
      } else if (this.splash.imageUrl && !this.imageFailed) {
        Image(this.splash.imageUrl)
          .objectFit(ImageFit.Cover)
          .width('100%').height('100%')
          .onError(() => { this.imageFailed = true })
      } else {
        // 品牌 fallback：内置插画 + 活动文案
        Column({ space: AppSpacing.x2 }) {
          Image($r('app.media.promo')).width('60%').height(200).objectFit(ImageFit.Contain)
          Text(this.splash.badge).fontColor(AppColors.brand).fontSize(13).fontWeight(FontWeight.Bold)
          Text(this.splash.title).fontSize(24).fontWeight(FontWeight.Bold)
          Text(this.splash.description).fontColor(AppColors.textSecondary).fontSize(14)
            .textAlign(TextAlign.Center)
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(AppSpacing.x6)
        .backgroundColor(AppColors.background)
      }
    }
    .width('100%').height('100%')
  }
}

// ── Onboarding (unchanged) ───────────────────────────────────────────────

@Component
export struct OnboardingPage {
  @ObjectLink store: AppStore

  build() {
    Column({ space: AppSpacing.x5 }) {
      Image($r('app.media.promo'))
        .width('100%')
        .height(220)
        .objectFit(ImageFit.Contain)
      Text('三步了解核心功能').fontSize(28).fontWeight(FontWeight.Bold)
      Text('首次安装展示，完成后不会重复出现。')
        .fontColor(AppColors.textSecondary)
      AppButton({
        label: '完成引导',
        onTap: () => this.store.goHome()
      })
    }
    .padding(AppSpacing.x6)
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
