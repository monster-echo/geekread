import webview from '@ohos.web.webview'
import { AppStore } from '../state/AppStore'
import { AppButton } from '../design_system/Components'
import { AppColors, AppSpacing } from '../theme/AppTokens'

const REDIRECT = 'mobilestarter://oauth'

// Web-based OAuth capture for social sign-in on HarmonyOS, which has no native
// Apple/Google SDK. The Web component intercepts the redirect scheme in-app, so
// no module.json5 deep-link registration is required. GitHub uses a PKCE code
// flow (plain challenge), Google an implicit id_token flow; Apple is unsupported
// here and surfaces a toast. Must be verified on a HarmonyOS device/simulator.
@Component
export struct SocialAuthSheet {
  @ObjectLink store: AppStore
  @Prop provider: string
  onDismiss: () => void = () => {}
  private controller: webview.WebviewController = new webview.WebviewController()
  @State url: string = ''
  private codeVerifier: string = ''

  aboutToAppear(): void {
    this.codeVerifier = this.randomString(64)
    this.url = this.buildAuthorizeUrl()
  }

  build() {
    Column() {
      Row() {
        Text(`正在通过 ${this.providerLabel()} 登录…`)
          .fontSize(16).fontColor(AppColors.text).layoutWeight(1)
        Button('取消').backgroundColor(Color.Transparent)
          .fontColor(AppColors.brand).onClick(() => this.onDismiss())
      }
      .width('100%').padding(AppSpacing.x4)
      if (this.url.length === 0) {
        Column({ space: AppSpacing.x3 }) {
          Text('未配置该登录方式的客户端 ID').fontColor(AppColors.textSecondary)
          AppButton({ label: '关闭', onTap: () => this.onDismiss() })
        }.padding(AppSpacing.x6).layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Web({ src: this.url, controller: this.controller })
          .domStorageAccess(true)
          .javaScriptAccess(true)
          .onLoadIntercept((event) => {
            const requestUrl = event.data.getRequestUrl()
            if (requestUrl.startsWith(REDIRECT)) {
              this.capture(requestUrl)
              return true
            }
            return false
          })
          .layoutWeight(1).width('100%')
      }
    }
    .width('100%').height('100%').backgroundColor(AppColors.background)
  }

  private buildAuthorizeUrl(): string {
    const clientId = this.clientId()
    if (clientId.length === 0) return ''
    if (this.provider === 'github') {
      const params = `client_id=${clientId}&redirect_uri=${REDIRECT}&response_type=code` +
        `&scope=read:user%20user:email&code_challenge=${this.codeVerifier}&code_challenge_method=plain`
      return `https://github.com/login/oauth/authorize?${params}`
    }
    if (this.provider === 'google') {
      const params = `client_id=${clientId}&redirect_uri=${REDIRECT}&response_type=token` +
        `&scope=openid%20profile%20email&nonce=${this.randomString(16)}`
      return `https://accounts.google.com/o/oauth2/v2/auth?${params}`
    }
    return ''
  }

  private capture(requestUrl: string): void {
    if (this.provider === 'github') {
      const code = this.queryParam(requestUrl, 'code')
      this.onDismiss()
      if (code.length > 0) {
        this.store.socialSignIn('github', '', code, REDIRECT, this.codeVerifier)
          .then(() => { if (this.store.signedIn) this.store.completeAuthentication() })
      }
    } else if (this.provider === 'google') {
      const idToken = this.fragmentParam(requestUrl, 'id_token')
        || this.queryParam(requestUrl, 'id_token')
      this.onDismiss()
      if (idToken.length > 0) {
        this.store.socialSignIn('google', idToken, '', '', '')
          .then(() => { if (this.store.signedIn) this.store.completeAuthentication() })
      }
    }
  }

  private clientId(): string {
    const config = this.store.authProviderConfig[this.provider] as Record<string, string> | undefined
    return config?.['clientId'] ?? ''
  }

  private providerLabel(): string {
    if (this.provider === 'github') return 'GitHub'
    if (this.provider === 'google') return 'Google'
    return this.provider
  }

  private queryParam(url: string, key: string): string {
    const query = url.split('?')[1] ?? ''
    return this.extractParam(query, key)
  }

  private fragmentParam(url: string, key: string): string {
    const fragment = url.split('#')[1] ?? ''
    return this.extractParam(fragment, key)
  }

  private extractParam(params: string, key: string): string {
    const parts = params.split('&')
    for (let i = 0; i < parts.length; i++) {
      const pair = parts[i].split('=')
      if (pair[0] === key) return decodeURIComponent(pair[1] ?? '')
    }
    return ''
  }

  private randomString(length: number): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
    let result = ''
    for (let i = 0; i < length; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return result
  }
}
