/**
 * @file AgreementViews.ets
 * @brief 协议 UI 唯一来源：勾选行 + 协议弹窗，登录页 / 手机号登录 / 注册共用一个组件，
 *        保证三处协议（用户协议 / 隐私政策 / 华为账号用户认证协议）完全一致。
 */
import { AppStore } from '../state/AppStore'
import { AppRoute } from '../navigation/AppRoute'
import { AppColors } from '../theme/AppTokens'
import { common } from '@kit.AbilityKit'

/** 华为账号用户认证协议页（系统浏览器打开，与 CortexTerminal2 一致） */
const HUAWEI_AUTH_URL: string =
  'https://privacy.consumer.huawei.com/legal/id/authentication-terms.htm?code=CN&language=zh-CN'

/**
 * 协议链接文字：我已阅读并同意《用户协议》与《隐私政策》以及《华为账号用户认证协议》。
 * 勾选行与协议弹窗共用，fontSize/textColor 由使用方控制。
 */
@Component
export struct AgreementLinks {
  store: AppStore = new AppStore()
  @Prop fontSize: number = 12
  @Prop textColor: ResourceColor = AppColors.textSecondary
  @Prop linkColor: ResourceColor = AppColors.brand

  build() {
    Text() {
      Span('我已阅读并同意')
        .fontColor(this.textColor)
        .fontSize(this.fontSize)
      Span('《用户协议》')
        .fontColor(this.linkColor)
        .fontSize(this.fontSize)
        .onClick(() => this.store.navigate(AppRoute.TermsOfService))
      Span('与')
        .fontColor(this.textColor)
        .fontSize(this.fontSize)
      Span('《隐私政策》')
        .fontColor(this.linkColor)
        .fontSize(this.fontSize)
        .onClick(() => this.store.navigate(AppRoute.PrivacyPolicy))
      Span('以及')
        .fontColor(this.textColor)
        .fontSize(this.fontSize)
      Span('《华为账号用户认证协议》')
        .fontColor(this.linkColor)
        .fontSize(this.fontSize)
        .onClick(() => this.openHuaweiAuth())
    }
  }

  private openHuaweiAuth(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
    ctx.openLink(HUAWEI_AUTH_URL)
  }
}

/** 协议勾选行：checkbox + 协议链接。勾选状态由父组件持有（@Prop agreed + onChange 回调）。 */
@Component
export struct AgreementRow {
  store: AppStore = new AppStore()
  @Prop agreed: boolean = false
  onChange: (value: boolean) => void = () => {}
  @Prop fontSize: number = 12

  build() {
    Row() {
      Checkbox()
        .width(20)
        .height(20)
        .select(this.agreed)
        .onChange((value: boolean) => this.onChange(value))
        .margin({ right: 8 })
      AgreementLinks({ store: this.store, fontSize: this.fontSize })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/** 协议弹窗：阅读并同意协议后才可登录。登录页 / 手机号登录 / 注册共用。 */
@CustomDialog
export struct AgreementDialog {
  controller: CustomDialogController
  store: AppStore = new AppStore()
  cancel: () => void = () => {}
  confirm: () => void = () => {}
  fontSize: number = 14

  build() {
    Column() {
      Text('用户协议与隐私条款')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.text)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 24, bottom: 16 })

      AgreementLinks({ store: this.store, fontSize: this.fontSize })
        .width('100%')
        .padding({ left: 24, right: 24 })
        .margin({ bottom: 24 })

      Row() {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .fontColor(AppColors.text)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .onClick(() => this.cancel())

        Button('同意并登录')
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(AppColors.brand)
          .fontColor(Color.White)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .onClick(() => this.confirm())
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 24 })
    }
    .backgroundColor(AppColors.surface)
    .borderRadius(16)
  }
}
