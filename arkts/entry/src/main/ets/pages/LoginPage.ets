/**
 * @file LoginPage.ets
 * @brief 登录页：逐字移植 CortexTerminal2 的 LoginPage.ets（华为一键登录 + 用户名/密码），
 *        并额外增加手机号登录入口。
 *
 * 移植说明（仅做了必要的适配）：
 *  - 后端调用 AuthService.* → geekread 的 AppStore（socialSignIn / signIn）
 *  - 颜色资源 $r('app.color.terminal_*') → AppColors
 *  - I18n.get('auth.*') → 中文硬编码
 *  - 导航 pageStack.pushPath → store.navigate
 *  - 验证码（SliderCaptchaDialog）：geekread 后端无 captcha 接口，已移除
 */
import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppColors } from '../theme/AppTokens'
import { authentication, loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { AgreementDialog, AgreementRow } from '../components/AgreementViews'

@Component
export struct LoginPage {
  @ObjectLink store: AppStore
  @State loginMode: string = 'huawei'
  @State isHuaweiLoading: boolean = false
  @State isPasswordLoading: boolean = false
  @State errorMessage: string = ''
  @State username: string = ''
  @State password: string = ''
  @State anonymousPhone: string = ''
  @State isAgreementAccepted: boolean = false

  private pendingUsername: string = ''
  private pendingPassword: string = ''

  private huaweiButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED)
      .onClickLoginWithHuaweiIDButton(
        (error: BusinessError | undefined,
         response: loginComponentManager.HuaweiIDCredential) => {
          if (error) {
            console.warn(`[HuaweiLogin] SDK error: code=${error.code} msg=${error.message}`)
            if (error.code === 1005300001) {
              this.agreementDialogController.open()
              return
            }
            if (error.code !== 1001502012 && error.code !== 1001502001) {
              this.errorMessage = '华为账号登录失败' + ` (${error.code})`
            }
            return
          }
          if (!this.isAgreementAccepted) {
            this.agreementDialogController.open()
            return
          }
          if (response) {
            const authCode = response.authorizationCode ?? ''
            if (authCode.length === 0) {
              this.errorMessage = '未获取到授权码'
              return
            }
            this.handleHuaweiLogin(authCode)
          }
        }
      )

  private agreementDialogController: CustomDialogController = new CustomDialogController({
    builder: AgreementDialog({
      store: this.store,
      cancel: () => {
        this.agreementDialogController.close()
      },
      confirm: () => {
        this.agreementDialogController.close()
        this.isAgreementAccepted = true
        this.huaweiButtonController.setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
        this.huaweiButtonController.continueLogin((error: BusinessError) => {
          if (error) {
            console.warn(`[HuaweiLogin] continueLogin error: code=${error.code} msg=${error.message}`)
          }
        })
      }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    cornerRadius: 16
  })

  aboutToAppear() {
    this.getAnonymousPhone()
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          this.BrandSection()

          if (this.loginMode === 'huawei') {
            this.HuaweiLoginSection()
            this.DividerSection()
            this.PhoneLoginEntry()
            this.PasswordLoginEntry()
          } else {
            this.PasswordFormSection()
            this.DividerSection()
            this.HuaweiLoginEntry()
            this.PhoneLoginEntry()
          }

          if (this.loginMode === 'huawei' && this.errorMessage.length > 0) {
            this.ErrorBanner()
          }
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      AgreementRow({
        store: this.store,
        agreed: this.isAgreementAccepted,
        fontSize: 12,
        onChange: (value: boolean) => {
          this.isAgreementAccepted = value
          this.huaweiButtonController.setAgreementStatus(
            value ? loginComponentManager.AgreementStatus.ACCEPTED : loginComponentManager.AgreementStatus.NOT_ACCEPTED
          )
        }
      })
      .width('100%')
      .padding({ left: 24, right: 24 })
      .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.background)
  }

  // ── Brand Area ──────────────────────────────────────────────────

  @Builder
  BrandSection() {
    Column() {
      Image($r('app.media.app_icon'))
        .width(96)
        .height(96)
        .borderRadius(24)
        .margin({ bottom: 18 })

      Text(this.store.config?.brand.appName ?? '极客译读')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.text)

      Text('GeekRead · 沉浸式技术阅读')
        .fontSize(14)
        .fontColor(AppColors.textSecondary)
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 24 })
  }

  // ── Huawei One-Click Login ──────────────────────────────────────

  @Builder
  HuaweiLoginSection() {
    Column() {
      if (this.anonymousPhone.length > 0) {
        Text(this.anonymousPhone)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.text)
          .textAlign(TextAlign.Center)
          .margin({ bottom: 8 })
      }

      Stack() {
        LoginWithHuaweiIDButton({
          params: {
            style: loginComponentManager.Style.BUTTON_RED,
            loginType: loginComponentManager.LoginType.QUICK_LOGIN,
            borderRadius: 24,
            supportDarkMode: true
          },
          controller: this.huaweiButtonController
        }).width('100%').height(48).constraintSize({ maxWidth: 400 })

        if (this.isHuaweiLoading) {
          Row() {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(AppColors.brand)
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(AppColors.surface)
          .opacity(0.7)
          .borderRadius(24)
          .constraintSize({ maxWidth: 400 })
          .hitTestBehavior(HitTestMode.Block)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24 })
    .margin({ top: 48 })
  }

  // ── Divider ─────────────────────────────────────────────────────

  @Builder
  DividerSection() {
    Row() {
      Divider()
        .layoutWeight(1)
        .color(AppColors.borderStrong)
      Text('其他登录方式')
        .fontSize(14)
        .fontColor(AppColors.textSecondary)
        .margin({ left: 16, right: 16 })
      Divider()
        .layoutWeight(1)
        .color(AppColors.borderStrong)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 24 })
    .padding({ left: 24, right: 24 })
  }

  // ── Phone Login Entry ───────────────────────────────────────────

  @Builder
  PhoneLoginEntry() {
    Column() {
      Button('使用手机号登录')
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: AppColors.borderStrong })
        .fontColor(AppColors.text)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          this.errorMessage = ''
          this.store.navigate(AppRoute.PhoneSignIn)
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 24, right: 24 })
    .margin({ top: 24 })
  }

  // ── Password Login Entry Button (from huawei mode) ──────────────

  @Builder
  PasswordLoginEntry() {
    Column() {
      Button('使用用户名和密码登录')
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: AppColors.borderStrong })
        .fontColor(AppColors.text)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          this.loginMode = 'password'
          this.errorMessage = ''
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 24, right: 24 })
    .margin({ top: 24 })
  }

  // ── Huawei Login Entry Button (from password mode) ──────────────

  @Builder
  HuaweiLoginEntry() {
    Column() {
      Button('使用华为账号登录')
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: AppColors.borderStrong })
        .fontColor(AppColors.text)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          this.loginMode = 'huawei'
          this.errorMessage = ''
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 400 })
    .padding({ left: 24, right: 24 })
    .margin({ top: 24 })
  }

  // ── Password Form (inline) ──────────────────────────────────────

   @Builder
  PasswordFormSection() {
    Column() {
      Text('用户名')
        .fontSize(14)
        .fontColor(AppColors.textSecondary)
        .width('100%')
        .margin({ bottom: 8 })

      TextInput({ placeholder: '请输入用户名', text: this.username })
        .width('100%')
        .height(48)
        .borderRadius(8)
        .backgroundColor(AppColors.surface)
        .fontColor(AppColors.text)
        .placeholderColor(AppColors.textSecondary)
        .onChange((value: string) => {
          this.username = value
          this.errorMessage = ''
        })

      Text('密码')
        .fontSize(14)
        .fontColor(AppColors.textSecondary)
        .width('100%')
        .margin({ top: 16, bottom: 8 })

      TextInput({ placeholder: '请输入密码', text: this.password })
        .type(InputType.Password)
        .width('100%')
        .height(48)
        .borderRadius(8)
        .backgroundColor(AppColors.surface)
        .fontColor(AppColors.text)
        .placeholderColor(AppColors.textSecondary)
        .onChange((value: string) => {
          this.password = value
          this.errorMessage = ''
        })

      if (this.errorMessage.length > 0) {
        Row() {
          Text('⚠')
            .fontSize(14)
            .fontColor(AppColors.error)
            .margin({ right: 8 })
          Text(this.errorMessage)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.error)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 16 })
      }

      Button() {
        if (this.isPasswordLoading) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(AppColors.onBrand)
        } else {
          Text('登录')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.username.length > 0 && this.password.length > 0 ? AppColors.onBrand : AppColors.textSecondary)
        }
      }
      .width('100%')
      .height(48)
      .borderRadius(24)
      .backgroundColor(this.username.length > 0 && this.password.length > 0 ? AppColors.brand : AppColors.surfaceMuted)
      .margin({ top: 20 })
      .enabled(this.username.length > 0 && this.password.length > 0 && !this.isPasswordLoading)
      .onClick(() => {
        this.handlePasswordLogin()
      })
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .margin({ top: 36 })
  }

  // ── Error Banner ────────────────────────────────────────────────

  @Builder
  ErrorBanner() {
    Row() {
      Text('⚠')
        .fontSize(14)
        .fontColor(AppColors.error)
        .margin({ right: 8 })
      Text(this.errorMessage)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.error)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .margin({ top: 16 })
  }

  // ── Handlers ────────────────────────────────────────────────────

  private getAnonymousPhone() {
    const authRequest = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest()
    authRequest.scopes = ['quickLoginAnonymousPhone']
    authRequest.state = util.generateRandomUUID()
    authRequest.forceAuthorization = false
    const controller = new authentication.AuthenticationController()
    controller.executeRequest(authRequest).then((response: authentication.AuthorizationWithHuaweiIDResponse) => {
      const phone: string = response.data?.extraInfo?.quickLoginAnonymousPhone as string ?? ''
      if (phone.length > 0) {
        console.info(`[HuaweiLogin] Got anonymous phone: ${phone}`)
        this.anonymousPhone = phone
      }
    }).catch((error: BusinessError) => {
      console.warn(`[HuaweiLogin] getAnonymousPhone error: code=${error.code} msg=${error.message}`)
    })
  }

  private async handleHuaweiLogin(authCode: string) {
    this.isHuaweiLoading = true
    this.errorMessage = ''
    try {
      const ok = await this.store.socialSignIn('huawei', '', authCode, '', '')
      this.isHuaweiLoading = false
      if (ok) {
        this.store.showToast('登录成功')
        this.store.completeAuthentication()
      }
    } catch (err) {
      console.warn(`[HuaweiLogin] Backend error: ${(err as Error).message}`)
      this.errorMessage = (err as Error).message || '华为账号登录失败'
      this.isHuaweiLoading = false
    }
  }

  private async handlePasswordLogin() {
    if (!this.isAgreementAccepted) {
      this.agreementDialogController.open()
      return
    }
    if (this.username.length === 0 || this.password.length === 0) {
      this.errorMessage = '请输入用户名和密码'
      return
    }
    this.pendingUsername = this.username
    this.pendingPassword = this.password

    this.isPasswordLoading = true
    this.errorMessage = ''
    try {
      const ok = await this.store.signIn(this.pendingUsername, this.pendingPassword)
      this.isPasswordLoading = false
      if (ok) {
        this.store.showToast('登录成功')
        this.store.completeAuthentication()
      }
    } catch (err) {
      this.errorMessage = (err as Error).message || '登录失败'
      this.isPasswordLoading = false
    }
  }
}
