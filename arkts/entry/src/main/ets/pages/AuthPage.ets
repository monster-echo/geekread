import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppButton, PageHeader } from '../design_system/Components'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { SocialAuthSheet } from './SocialAuthSheet'

export enum AuthMode {
  SignIn,
  SignUp,
  Phone,
  Forgot,
  Verify,
  Reset
}

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

  build() {
    Stack() {
      Column() {
        PageHeader({ store: this.store, title: this.title() })
      Column({ space: AppSpacing.x4 }) {
        Text(this.title())
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.text)
          .width('100%')
        Text('安全同步你的会员、订单与偏好设置。')
          .fontColor(AppColors.textSecondary)
          .width('100%')
        if (this.mode !== AuthMode.Verify && this.mode !== AuthMode.Reset) {
          TextInput({
            placeholder: this.accountPlaceholder(),
            text: this.email
          })
            .height(52)
            .backgroundColor(AppColors.surface)
            .borderRadius(AppRadii.control)
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
            .borderRadius(AppRadii.control)
            .onChange(value => this.password = value)
        }
        if (this.mode === AuthMode.SignUp) {
          TextInput({ placeholder: '用户名', text: this.username })
            .height(52)
            .backgroundColor(AppColors.surface)
            .borderRadius(AppRadii.control)
            .onChange(value => this.username = value)
        }
        AppButton({
          label: this.store.busy ? '正在处理…' : this.action(),
          onTap: () => this.submit()
        })
        if (this.mode === AuthMode.SignIn) {
          Text('其他登录方式')
            .fontSize(12)
            .fontColor(AppColors.textSecondary)
          AuthProviderRow({ store: this.store, onSocial: (provider) => this.beginSocial(provider) })
          Text('忘记密码')
            .fontColor(AppColors.brand)
            .onClick(() => this.store.navigate(AppRoute.ForgotPassword))
          Text('创建账号')
            .fontColor(AppColors.brand)
            .onClick(() => this.store.navigate(AppRoute.SignUp))
        }
        if (this.requiresConsent()) {
          Row({ space: AppSpacing.x1 }) {
            Checkbox()
              .select(this.consentAgreed)
              .onChange((value: boolean) => { this.consentAgreed = value })
            Text('我已阅读并同意').fontSize(12).fontColor(AppColors.textSecondary)
              .onClick(() => { this.consentAgreed = !this.consentAgreed })
            Text('用户协议')
              .fontSize(12).fontColor(AppColors.brand)
              .onClick(() => this.store.navigate(AppRoute.TermsOfService))
            Text('与').fontSize(12).fontColor(AppColors.textSecondary)
              .onClick(() => { this.consentAgreed = !this.consentAgreed })
            Text('隐私政策')
              .fontSize(12).fontColor(AppColors.brand)
              .onClick(() => this.store.navigate(AppRoute.PrivacyPolicy))
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }
      }
      .padding(AppSpacing.x6)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
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
  }

  private beginSocial(provider: string): void {
    if (!this.ensureConsent()) return
    if (provider === 'phone') {
      this.store.navigate(AppRoute.PhoneSignIn)
      return
    }
    if (provider === 'apple') {
      this.store.showToast('HarmonyOS 暂不支持 Apple 登录', true)
      return
    }
    this.socialProvider = provider
  }

  private async submit(): Promise<void> {
    if (this.store.busy) {
      return
    }
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
        if (!this.phoneCodeSent) {
          if (await this.store.requestPhoneCode(this.email)) {
            this.phoneCodeSent = true
            this.store.showToast('验证码已发送')
          }
          return
        }
        if (await this.store.verifyPhoneCode(this.email, this.password)) {
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
    this.store.showToast('请先阅读并同意用户协议与隐私政策', true)
    return false
  }

  private requiresConsent(): boolean {
    return this.mode === AuthMode.SignIn || this.mode === AuthMode.SignUp
  }

  private accountPlaceholder(): string {
    if (this.mode === AuthMode.Phone) return '+86 13800000000'
    if (this.mode === AuthMode.SignIn) return '用户名、邮箱或手机号'
    return '邮箱'
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

@Component
struct AuthProviderRow {
  @ObjectLink store: AppStore
  onSocial: (provider: string) => void = () => {}

  build() {
    Row({ space: AppSpacing.x5 }) {
      AuthProviderButton({
        label: 'Apple',
        icon: $r('app.media.apple'),
        iconStyle: AuthIconStyle.Monochrome,
        isEnabled: this.store.authProviders['apple'] === true,
        onTap: () => this.onSocial('apple')
      })
      AuthProviderButton({
        label: 'Google',
        icon: $r('app.media.google'),
        iconStyle: AuthIconStyle.Branded,
        isEnabled: this.store.authProviders['google'] === true,
        onTap: () => this.onSocial('google')
      })
      AuthProviderButton({
        label: 'GitHub',
        icon: $r('app.media.github'),
        iconStyle: AuthIconStyle.Monochrome,
        isEnabled: this.store.authProviders['github'] === true,
        onTap: () => this.onSocial('github')
      })
      AuthProviderButton({
        label: '手机号',
        icon: $r('app.media.phone'),
        iconStyle: AuthIconStyle.Monochrome,
        isEnabled: this.store.authProviders['phone'] === true,
        onTap: () => this.onSocial('phone')
      })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }
}

enum AuthIconStyle {
  Branded,
  Monochrome
}

@Component
struct AuthProviderButton {
  @Prop label: string
  @Prop icon: Resource
  @Prop iconStyle: AuthIconStyle = AuthIconStyle.Monochrome
  @Prop isEnabled: boolean = false
  onTap: () => void = () => {}

  build() {
    Column({ space: AppSpacing.x1 }) {
      Column() {
        if (this.iconStyle === AuthIconStyle.Monochrome) {
          Image(this.icon)
            .width(24)
            .height(24)
            .fillColor(AppColors.text)
        } else {
          Image(this.icon)
            .width(24)
            .height(24)
        }
      }
        .width(52)
        .height(52)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppColors.surface)
        .border({ width: 1, color: AppColors.border })
        .borderRadius(26)
      Text(this.label).fontSize(12).fontColor(AppColors.textSecondary)
    }
    .opacity(this.isEnabled ? 1 : 0.38)
    .enabled(this.isEnabled)
    .onClick(this.onTap)
  }
}
