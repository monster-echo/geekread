import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppButton, PageHeader } from '../design_system/Components'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { SocialAuthSheet } from './SocialAuthSheet'
import { authentication, loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { telemetry } from '../telemetry/Telemetry'
import { AgreementDialog, AgreementRow } from '../components/AgreementViews'

export enum AuthMode {
  SignIn,
  SignUp,
  Phone,
  Forgot,
  Verify,
  Reset
}

const TERMS_TAG = 'terms'
const PRIVACY_TAG = 'privacy'

@Component
export struct AuthPage {
  @ObjectLink store: AppStore
  @Prop mode: AuthMode
  @State email: string = ''
  @State password: string = ''
  @State username: string = ''
  @State phoneCodeSent: boolean = false
  @State consentAgreed: boolean = false
  @State socialProvider: string = ''
  @State isHuaweiLoading: boolean = false
  @State isPasswordLoading: boolean = false
  @State errorMessage: string = ''
  // 华为账号绑定的匿名手机号（如 177******43），进页面静默预取号用于展示
  @State huaweiAnonymousPhone: string = ''
  // 预取号失败信息（scope 未授权 / 网络异常等），透出原因
  @State huaweiPrefetchError: string = ''
  // 登录方式：'huawei' 一键登录（默认）| 'password' 邮箱/密码
  @State loginMode: string = 'huawei'

  private huaweiButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED)
      .onClickLoginWithHuaweiIDButton(
        (error: BusinessError, response: loginComponentManager.HuaweiIDCredential) => {
          if (error) {
            // 1005300001 = 未同意协议（NOT_ACCEPTED 状态下 SDK 拦截）→ 弹协议弹窗
            if (error.code === 1005300001) {
              this.openAgreement()
              return
            }
            // 1001502012/1001502001 = 用户取消/重复授权，静默忽略
            if (error.code !== 1001502012 && error.code !== 1001502001) {
              this.errorMessage = `华为登录失败 (${error.code})`
            }
            return
          }
          if (!this.consentAgreed) {
            this.openAgreement()
            return
          }
          const authCode = response?.authorizationCode ?? ''
          if (authCode.length === 0) {
            this.errorMessage = '未获取到华为授权码'
            return
          }
          this.handleHuaweiLogin(authCode)
        }
      )

  private agreementDialogController: CustomDialogController = new CustomDialogController({
    builder: AgreementDialog({
      store: this.store,
      cancel: () => { this.agreementDialogController.close() },
      confirm: () => {
        this.agreementDialogController.close()
        this.setConsent(true)
        this.huaweiButtonController.setAgreementStatus(loginComponentManager.AgreementStatus.ACCEPTED)
        this.huaweiButtonController.continueLogin((error: BusinessError) => {
          if (error) {
            this.errorMessage = `继续登录失败 (${error.code})`
          }
        })
      }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    cornerRadius: 16
  })

  aboutToAppear(): void {
    this.prefetchHuaweiPhone()
  }

  /**
   * 预取华为账号匿名手机号（quickLoginAnonymousPhone scope 静默返回）。
   * 参照 CortexTerminal2：scope 只用 quickLoginAnonymousPhone、forceAuthorization=false、
   * 带 state、AuthenticationController 不传 context、promise 风格。
   */
  private prefetchHuaweiPhone(): void {
    if (this.store.authProviders['huawei'] !== true) return
    try {
      const req = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest()
      req.scopes = ['quickLoginAnonymousPhone']
      req.state = util.generateRandomUUID()
      req.forceAuthorization = false
      const controller = new authentication.AuthenticationController()
      controller.executeRequest(req).then((resp: authentication.AuthorizationWithHuaweiIDResponse) => {
        const phone = resp.data?.extraInfo?.quickLoginAnonymousPhone as string ?? ''
        if (phone.length > 0) {
          this.huaweiAnonymousPhone = phone
        } else {
          console.error('[geekread][huawei-prefetch] no quickLoginAnonymousPhone in extraInfo')
          this.huaweiPrefetchError = '未返回匿名手机号'
        }
      }).catch((error: BusinessError) => {
        console.error(`[geekread][huawei-prefetch] failed: code=${error.code} msg=${error.message}`)
        this.huaweiPrefetchError = `取号失败 code=${error.code}`
      })
    } catch (e) {
      console.error('[geekread][huawei-prefetch] exception')
      this.huaweiPrefetchError = '预取号异常'
    }
  }

  build() {
    Stack() {
      Column() {
        PageHeader({ store: this.store, title: this.title() })
        if (this.mode === AuthMode.SignIn) {
          this.SignInContent()
        } else {
          this.FormContent()
        }
      }
      .width('100%')
      .height('100%')
      if (this.socialProvider.length > 0) {
        SocialAuthSheet({
          store: this.store,
          provider: this.socialProvider,
          onDismiss: () => { this.socialProvider = '' }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ── 登录（SignIn）：照搬 CortexTerminal2 两段式一键登录 + 密码登录 ──

  @Builder
  SignInContent() {
    Scroll() {
      Column({ space: AppSpacing.x4 }) {
        Text('欢迎登录极客译读 :)')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.text)
          .width('100%')
        Text('安全同步你的会员、订单与偏好设置。')
          .fontColor(AppColors.textSecondary)
          .width('100%')

        if (this.loginMode === 'huawei') {
          this.HuaweiLoginSection()
          this.DividerSection()
          this.OtherLoginEntry('手机号登录', () => this.store.navigate(AppRoute.PhoneSignIn))
          this.OtherLoginEntry('邮箱/密码登录', () => { this.loginMode = 'password'; this.errorMessage = '' })
        } else {
          this.PasswordLoginSection()
          this.DividerSection()
          this.OtherLoginEntry('华为账号登录', () => { this.loginMode = 'huawei'; this.errorMessage = '' })
          this.OtherLoginEntry('手机号登录', () => this.store.navigate(AppRoute.PhoneSignIn))
        }

        if (this.errorMessage.length > 0) {
          this.ErrorBanner()
        }
      }
      .padding(AppSpacing.x6)
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)

    AgreementRow({
      store: this.store,
      agreed: this.consentAgreed,
      fontSize: 12,
      onChange: (value: boolean) => { this.setConsent(value) }
    })
    .width('100%')
    .padding({ left: AppSpacing.x6, right: AppSpacing.x6, top: AppSpacing.x3, bottom: AppSpacing.x3 })
  }

  // 华为一键登录：匿名手机号 + 一键登录按钮
  @Builder
  HuaweiLoginSection() {
    Column() {
      if (this.huaweiAnonymousPhone.length > 0) {
        Text(this.huaweiAnonymousPhone)
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
            LoadingProgress().width(24).height(24).color(AppColors.brand)
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

      if (this.huaweiPrefetchError.length > 0) {
        Text(`一键登录取号失败：${this.huaweiPrefetchError}`)
          .fontSize(12)
          .fontColor(AppColors.textSecondary)
          .width('100%')
          .margin({ top: AppSpacing.x2 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  // 邮箱/密码登录
  @Builder
  PasswordLoginSection() {
    Column() {
      TextInput({ placeholder: '邮箱', text: this.email })
        .height(52)
        .backgroundColor(AppColors.surface)
        .border({ width: 1, color: AppColors.borderStrong })
        .borderRadius(AppRadii.control)
        .placeholderColor(AppColors.textSecondary)
        .onChange(value => { this.email = value; this.errorMessage = '' })

      TextInput({ placeholder: '密码', text: this.password })
        .type(InputType.Password)
        .height(52)
        .backgroundColor(AppColors.surface)
        .border({ width: 1, color: AppColors.borderStrong })
        .borderRadius(AppRadii.control)
        .placeholderColor(AppColors.textSecondary)
        .onChange(value => { this.password = value; this.errorMessage = '' })

      AppButton({
        label: this.isPasswordLoading ? '正在登录…' : '登录',
        onTap: () => this.handlePasswordLogin()
      })

      Row({ space: AppSpacing.x2 }) {
        Text('忘记密码')
          .fontSize(12)
          .fontColor(AppColors.brand)
          .onClick(() => this.store.navigate(AppRoute.ForgotPassword))
        Text('创建账号')
          .fontSize(12)
          .fontColor(AppColors.brand)
          .onClick(() => this.store.navigate(AppRoute.SignUp))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
  }

  // 其他登录方式入口（全宽描边按钮）
  @Builder
  OtherLoginEntry(label: string, onTap: () => void) {
    Button(label)
      .width('100%')
      .height(48)
      .borderRadius(24)
      .backgroundColor(Color.Transparent)
      .border({ width: 1, color: AppColors.borderStrong })
      .fontColor(AppColors.text)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .onClick(() => { onTap() })
  }

  @Builder
  DividerSection() {
    Row() {
      Divider().layoutWeight(1).color(AppColors.borderStrong)
      Text('其他方式')
        .fontSize(14)
        .fontColor(AppColors.textSecondary)
        .margin({ left: 16, right: 16 })
      Divider().layoutWeight(1).color(AppColors.borderStrong)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ErrorBanner() {
    Row() {
      Text('⚠')
        .fontSize(14)
        .fontColor(AppColors.brand)
        .margin({ right: 8 })
      Text(this.errorMessage)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.brand)
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: AppSpacing.x2 })
  }

  // ── 非 SignIn 模式（SignUp / Phone / Forgot / Verify / Reset）：沿用原表单 ──

  @Builder
  FormContent() {
    Column({ space: AppSpacing.x4 }) {
      if (this.mode !== AuthMode.Verify && this.mode !== AuthMode.Reset) {
        TextInput({
          placeholder: this.accountPlaceholder(),
          text: this.email
        })
          .height(52)
          .backgroundColor(AppColors.surface)
          .border({ width: 1, color: AppColors.borderStrong })
          .borderRadius(AppRadii.control)
          .placeholderColor(AppColors.textSecondary)
          .onChange(value => this.email = value)
      } else {
        Text(this.store.recoveryEmail)
          .fontColor(AppColors.textSecondary)
          .width('100%')
      }
      if (this.mode !== AuthMode.Forgot &&
        (this.mode !== AuthMode.Phone || this.phoneCodeSent)) {
        TextInput({
          placeholder: this.mode === AuthMode.Verify ||
            this.mode === AuthMode.Phone ? '验证码' :
            this.mode === AuthMode.Reset ? '新密码' : '密码',
          text: this.password
        })
          .height(52)
          .type(this.mode === AuthMode.Verify ||
            this.mode === AuthMode.Phone ? InputType.Number : InputType.Password)
          .backgroundColor(AppColors.surface)
          .border({ width: 1, color: AppColors.borderStrong })
          .borderRadius(AppRadii.control)
          .placeholderColor(AppColors.textSecondary)
          .onChange(value => this.password = value)
      }
      if (this.mode === AuthMode.SignUp) {
        TextInput({ placeholder: '用户名', text: this.username })
          .height(52)
          .backgroundColor(AppColors.surface)
          .border({ width: 1, color: AppColors.borderStrong })
          .borderRadius(AppRadii.control)
          .placeholderColor(AppColors.textSecondary)
          .onChange(value => this.username = value)
      }
      AppButton({
        label: this.store.busy ? '正在处理…' : this.action(),
        onTap: () => this.submit()
      })
      if (this.requiresConsent()) {
        AgreementRow({
          store: this.store,
          agreed: this.consentAgreed,
          fontSize: 12,
          onChange: (value: boolean) => { this.setConsent(value) }
        })
        .width('100%')
      }
    }
    .padding(AppSpacing.x6)
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
  }

  // ── 处理函数 ──

  private openAgreement(): void {
    this.agreementDialogController.open()
  }

  private setConsent(agreed: boolean): void {
    this.consentAgreed = agreed
    this.huaweiButtonController.setAgreementStatus(
      agreed ? loginComponentManager.AgreementStatus.ACCEPTED : loginComponentManager.AgreementStatus.NOT_ACCEPTED
    )
  }

  private async handleHuaweiLogin(authCode: string): Promise<void> {
    if (this.store.busy) return
    this.isHuaweiLoading = true
    this.errorMessage = ''
    try {
      const ok = await this.store.socialSignIn('huawei', '', authCode, '', '')
      if (ok) {
        this.store.showToast('登录成功')
        this.store.completeAuthentication()
      }
    } finally {
      this.isHuaweiLoading = false
    }
  }

  private async handlePasswordLogin(): Promise<void> {
    if (this.store.busy) return
    if (!this.ensureConsent()) return
    telemetry.click('auth_submit_signin', 'auth')
    this.isPasswordLoading = true
    this.errorMessage = ''
    try {
      const ok = await this.store.signIn(this.email, this.password)
      if (ok) {
        this.store.showToast('登录成功')
        this.store.completeAuthentication()
      } else {
        this.isPasswordLoading = false
      }
    } catch (e) {
      this.isPasswordLoading = false
    }
  }

  private beginSocial(provider: string): void {
    telemetry.click(`social_${provider}`, 'auth')
    if (!this.ensureConsent()) return
    if (provider === 'phone') {
      this.store.navigate(AppRoute.PhoneSignIn)
      return
    }
    this.socialProvider = provider
  }

  private async submit(): Promise<void> {
    if (this.store.busy) {
      return
    }
    telemetry.click(`auth_submit_${this.mode}`, 'auth')
    switch (this.mode) {
      case AuthMode.Forgot:
        if (await this.store.requestPasswordReset(this.email)) {
          this.store.navigate(AppRoute.VerifyEmail)
        }
        return
      case AuthMode.Verify:
        if (await this.store.verifyPasswordReset(this.password)) {
          this.store.navigate(AppRoute.ResetPassword)
        }
        return
      case AuthMode.Reset:
        if (await this.store.resetPassword(this.password)) {
          this.store.showToast('密码修改成功')
          this.store.replaceAll(AppRoute.SignIn)
        }
        return
      case AuthMode.Phone:
        if (!this.ensureConsent()) return
        if (!this.phoneCodeSent) {
          if (await this.store.requestPhoneCode(this.normalizePhone(this.email))) {
            this.phoneCodeSent = true
            this.store.showToast('验证码已发送')
          }
          return
        }
        if (await this.store.verifyPhoneCode(this.normalizePhone(this.email), this.password)) {
          this.store.showToast('手机号登录成功')
          this.store.completeAuthentication()
        }
        return
      case AuthMode.SignUp:
        if (!this.ensureConsent()) return
        if (!await this.store.signUp(this.email, this.password, this.username, this.termsRevision())) {
          return
        }
        this.store.showToast('账号创建成功')
        this.store.completeAuthentication()
        return
      case AuthMode.SignIn:
        if (!this.ensureConsent()) return
        if (!await this.store.signIn(this.email, this.password)) {
          return
        }
        this.store.showToast('登录成功')
        this.store.completeAuthentication()
    }
  }

  private ensureConsent(): boolean {
    if (this.consentAgreed) return true
    this.openAgreement()
    return false
  }

  private requiresConsent(): boolean {
    return this.mode === AuthMode.SignIn || this.mode === AuthMode.SignUp || this.mode === AuthMode.Phone
  }

  private accountPlaceholder(): string {
    if (this.mode === AuthMode.Phone) return '请输入手机号'
    if (this.mode === AuthMode.SignIn) return '用户名、邮箱或手机号'
    return '邮箱'
  }

  /** 手机号：国内默认 +86，用户只输 11 位，提交时自动补国家码。 */
  private normalizePhone(input: string): string {
    const t = input.trim()
    if (t.length === 0) return t
    return t.startsWith('+') ? t : `+86${t}`
  }

  private termsRevision(): string {
    const legal = this.store.config?.legal ?? []
    for (let i = 0; i < legal.length; i++) {
      if (legal[i].type === 'terms') return legal[i].revision
    }
    return legal.length > 0 ? legal[0].revision : 'unknown'
  }

  private title(): string {
    switch (this.mode) {
      case AuthMode.SignIn: return '欢迎回来'
      case AuthMode.SignUp: return '创建账号'
      case AuthMode.Phone: return '手机号登录'
      case AuthMode.Forgot: return '找回密码'
      case AuthMode.Verify: return '验证邮箱'
      case AuthMode.Reset: return '设置新密码'
    }
  }

  private action(): string {
    switch (this.mode) {
      case AuthMode.SignIn: return '登录'
      case AuthMode.SignUp: return '注册'
      case AuthMode.Phone: return this.phoneCodeSent ? '验证并登录' : '发送验证码'
      case AuthMode.Forgot: return '发送验证码'
      case AuthMode.Verify: return '确认验证码'
      case AuthMode.Reset: return '确认修改'
    }
  }
}
