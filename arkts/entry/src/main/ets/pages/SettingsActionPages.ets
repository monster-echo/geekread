import common from '@ohos.app.ability.common'
import { bundleManager } from '@kit.AbilityKit'
import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppButton, AppListRow, PageHeader } from '../design_system/Components'
import { AppIcon, AppIconName } from '../design_system/AppIcon'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { LegalDocument } from '../domain/Models'
import { AvatarCropEditor } from '../media/AvatarCropEditor'
import {
  pickAvatarPixelMap,
  cropPixelMapToAvatar,
  CropRect,
  type AvatarSource
} from '../media/AvatarPicker'
import { appString, AppString } from '../localization/AppStrings'
import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'

@Component
export struct AccountSecurityPage {
  @ObjectLink store: AppStore
  @State currentPassword: string = ''
  @State newPassword: string = ''

  private displayEmail(): string {
    const email = this.store.user?.email ?? ''
    if (email.length === 0) return '未设置'
    // 伪邮箱（华为/手机号自动生成的 xxx@phone.invalid）不展示
    const isFake = email.endsWith('@phone.invalid') || email.endsWith('@invalid.local')
    return isFake ? '未设置' : email
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: '账户与安全' })
      Column({ space: AppSpacing.x4 }) {
        AppListRow({ store: this.store, label: '登录邮箱',
          value: this.displayEmail() })
        PasswordInput({ label: '当前密码（首次设置可留空）', value: this.currentPassword,
          changed: value => this.currentPassword = value })
        PasswordInput({ label: '至少 8 位新密码', value: this.newPassword,
          changed: value => this.newPassword = value })
        AppButton({ label: this.store.busy ? '修改中…' : '修改密码',
          icon: AppIconName.Lock, onTap: () => this.submit() })
        AppButton({ label: '退出全部设备',
          destructive: true,
          onTap: () => this.confirmSignOutAll() })
      }.padding(AppSpacing.x4).layoutWeight(1)
    }.width('100%').height('100%')
  }

  private async submit(): Promise<void> {
    if (this.newPassword.length < 8) {
      this.store.showToast('新密码至少需要 8 位', true)
      return
    }
    if (await this.store.changePassword(this.currentPassword, this.newPassword)) {
      this.store.replaceAll(AppRoute.SignIn)
    }
  }

  private confirmSignOutAll(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '退出全部设备？',
      message: '所有设备上的登录会话将立即失效，需重新登录。',
      buttons: [
        { text: '取消', color: '#667085' },
        { text: '退出全部', color: '#D24B4B' }
      ]
    }).then(async result => {
      if (result.index === 1) {
        await this.store.signOutAll()
        this.store.replaceAll(AppRoute.SignIn)
      }
    })
  }
}

@Component
struct PasswordInput {
  @Prop label: string
  @Prop value: string
  changed: (value: string) => void = () => {}
  build() {
    TextInput({ placeholder: this.label, text: this.value })
      .height(52).type(InputType.Password).backgroundColor(AppColors.surface)
      .border({ width: 1, color: AppColors.borderStrong })
      .borderRadius(AppRadii.control).onChange(this.changed)
  }
}

@Component
export struct ChoicePreferencePage {
  @ObjectLink store: AppStore
  @Prop route: AppRoute
  @State selected: string = ''

  aboutToAppear(): void {
    const settings = this.store.user?.settings
    if (this.route === AppRoute.Appearance) this.selected = this.store.theme
    if (this.route === AppRoute.Language) this.selected = this.store.language
    if (this.route === AppRoute.TextSize) this.selected = String(this.store.textScale)
    if (this.route === AppRoute.TranslationDisplay) this.selected = this.store.translationDisplayMode
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: this.title() })
      Column({ space: AppSpacing.x3 }) {
        if (this.route === AppRoute.TextSize) {
          // 字号用滑块（连续调节），显示当前档位名（不显示原始数值）
          Column({ space: AppSpacing.x4 }) {
            Row() {
              Text(this.scaleLabel(Number(this.selected))).fontSize(16).fontColor(AppColors.text).layoutWeight(1)
            }
            Slider({ value: Number(this.selected), min: 0.85, max: 1.3, step: 0.05 })
              .blockColor(AppColors.brand)
              .selectedColor(AppColors.brand)
              .onChange((value: number) => { this.selected = String(value) })
            Row({ space: AppSpacing.x2 }) {
              Text(appString(AppString.TextSmall, this.store.language))
                .fontSize(12).fontColor(AppColors.textSecondary).layoutWeight(1)
              Text(appString(AppString.TextExtraLarge, this.store.language))
                .fontSize(12).fontColor(AppColors.textSecondary)
            }.width('100%')
          }.padding(AppSpacing.x4).backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
        } else {
          Column() {
            ForEach(this.options(), (option: string) => {
              Row({ space: AppSpacing.x3 }) {
                Radio({ group: this.groupName(), value: option }).checked(option === this.selected)
                  .onChange((isChecked: boolean) => { if (isChecked) this.selected = option })
                Text(this.label(option)).fontSize(16).fontColor(AppColors.text)
                  .layoutWeight(1)
                  .onClick(() => this.selected = option)
              }
              .width('100%').height(52).padding({ left: AppSpacing.x4, right: AppSpacing.x4 })
              .backgroundColor(AppColors.surface)
              .onClick(() => this.selected = option)
            })
          }.borderRadius(AppRadii.card)
        }
        AppButton({ label: this.store.busy
          ? appString(AppString.Saving, this.store.language)
          : appString(AppString.SaveSettings, this.store.language),
          icon: AppIconName.Check, onTap: () => this.save() })
      }.padding(AppSpacing.x4).layoutWeight(1)
    }.width('100%').height('100%')
  }

  private groupName(): string {
    return `pref_${this.route}`
  }

  // 字号档位名：把缩放值就近映射到 较小/标准/较大/特大（不显示 0.8500 等原始值）
  private scaleLabel(scale: number): string {
    if (scale <= 0.95) return appString(AppString.TextSmall, this.store.language)
    if (scale <= 1.05) return appString(AppString.TextStandard, this.store.language)
    if (scale <= 1.2) return appString(AppString.TextLarge, this.store.language)
    return appString(AppString.TextExtraLarge, this.store.language)
  }

  private save(): void {
    if (this.route === AppRoute.Appearance) this.store.saveSetting('theme', this.selected)
    if (this.route === AppRoute.Language) this.store.saveSetting('language', this.selected)
    if (this.route === AppRoute.TextSize) this.store.saveSetting('textScale', Number(this.selected))
    if (this.route === AppRoute.TranslationDisplay) this.store.saveSetting('translationDisplay', this.selected)
  }

  private options(): string[] {
    if (this.route === AppRoute.Appearance) return ['system', 'light', 'dark']
    if (this.route === AppRoute.Language) {
      return ['zh-CN', 'zh-TW', 'en-US', 'ms-MY', 'id-ID', 'th-TH', 'vi-VN', 'ar-SA', 'ja-JP', 'ko-KR']
    }
    if (this.route === AppRoute.TranslationDisplay) return ['original', 'both', 'translation']
    return ['0.9', '1', '1.15', '1.3']
  }

  private label(value: string): string {
    if (value === 'system') return appString(AppString.ThemeSystem, this.store.language)
    if (value === 'light') return appString(AppString.ThemeLight, this.store.language)
    if (value === 'dark') return appString(AppString.ThemeDark, this.store.language)
    if (value === 'zh-CN') return '简体中文'
    if (value === 'zh-TW') return '繁體中文'
    if (value === 'en-US') return 'English'
    if (value === 'ms-MY') return 'Bahasa Melayu'
    if (value === 'id-ID') return 'Bahasa Indonesia'
    if (value === 'th-TH') return 'ไทย'
    if (value === 'vi-VN') return 'Tiếng Việt'
    if (value === 'ar-SA') return 'العربية'
    if (value === 'ja-JP') return '日本語'
    if (value === 'ko-KR') return '한국어'
    if (value === '0.9') return appString(AppString.TextSmall, this.store.language)
    if (value === '1') return appString(AppString.TextStandard, this.store.language)
    if (value === '1.15') return appString(AppString.TextLarge, this.store.language)
    if (value === '1.3') return appString(AppString.TextExtraLarge, this.store.language)
    if (value === 'original') return '只看原文'
    if (value === 'both') return '双语对照'
    if (value === 'translation') return '只看译文'
    return value
  }

  private title(): string {
    if (this.route === AppRoute.Appearance) return appString(AppString.Appearance, this.store.language)
    if (this.route === AppRoute.Language) return appString(AppString.Language, this.store.language)
    if (this.route === AppRoute.TranslationDisplay) return '翻译显示'
    return appString(AppString.TextSize, this.store.language)
  }
}

@Component
export struct LegalPage {
  @ObjectLink store: AppStore
  build() {
    Column() {
      PageHeader({ store: this.store, title: '协议与政策' })
      Column({ space: AppSpacing.x2 }) {
        // 入口列表：点进单篇
        ForEach(this.store.config?.legal ?? [], (document: LegalDocument) => {
          Row({ space: AppSpacing.x3 }) {
            Text(document.title).fontSize(16).fontColor(AppColors.text).layoutWeight(1)
            Text(`版本 ${document.revision}`).fontSize(12).fontColor(AppColors.textSecondary)
          }
          .width('100%').height(56).padding({ left: AppSpacing.x4, right: AppSpacing.x4 })
          .backgroundColor(AppColors.surface)
          .onClick(() => this.store.navigate(document.type === 'privacy' ? AppRoute.PrivacyPolicy : AppRoute.TermsOfService))
        })
      }.padding(AppSpacing.x4).layoutWeight(1)
    }.width('100%').height('100%')
  }
}

@Component
export struct LegalDocumentPage {
  @ObjectLink store: AppStore
  @Prop type: string
  private mdController: MarkdownController = new MarkdownController()

  aboutToAppear(): void {
    // 深色模式适配：库默认文字色是写死的暗色，这里用 $r 资源（base/dark 自动切换）覆盖
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
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: this.title() })
      Scroll() {
        Column({ space: AppSpacing.x3 }) {
          if (this.document() === undefined) {
            Text('当前 App 尚未配置该协议文档。').fontColor(AppColors.textSecondary)
          } else {
            Text(`版本 ${this.document()?.revision ?? ''}`).fontColor(AppColors.textSecondary)
            Markdown({ controller: this.mdController, text: this.document()?.content ?? '' })
          }
        }.alignItems(HorizontalAlign.Start).padding(AppSpacing.x4).width('100%')
      }.layoutWeight(1)
      .align(Alignment.TopStart)
    }.width('100%').height('100%')
  }

  private document(): LegalDocument | undefined {
    const documents = this.store.config?.legal ?? []
    for (let i = 0; i < documents.length; i++) {
      if (documents[i].type === this.type) return documents[i]
    }
    return undefined
  }

  private title(): string {
    return this.document()?.title ?? (this.type === 'privacy' ? '隐私政策' : '用户协议')
  }
}

@Component
export struct AboutPage {
  @ObjectLink store: AppStore
  @State version: string = ''

  aboutToAppear(): void {
    // 从系统读真实版本（versionName + versionCode），与上架版本一致
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo) => {
        this.version = `${info.versionName} (${info.versionCode})`
      })
      .catch((e: object) => {
        this.version = '未知'
      })
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: '关于与版本' })
      Column() {
        AppListRow({ store: this.store, label: '产品',
          value: this.store.config?.brand.appName ?? 'MobileUI' })
        AppListRow({ store: this.store, label: '客户端版本', value: this.version })
        AppListRow({ store: this.store, label: '配置版本',
          value: `v${this.store.config?.version ?? 0}` })
        AppListRow({ store: this.store, label: '服务状态',
          value: this.store.online ? '在线' : '离线缓存' })
      }.margin(AppSpacing.x4).backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
    }.width('100%').height('100%')
  }
}

@Component
export struct ProfileEditPage {
  @ObjectLink store: AppStore
  @State username: string = ''
  @State displayName: string = ''
  @State bio: string = ''
  @State avatarUrl: string = ''
  // 是否显示裁剪编辑器覆盖层
  @State editing: boolean = false
  // 待裁剪头像（PixelMap 为 SDK 对象，不能作为 @State，用普通成员保存）
  private picked: AvatarSource | null = null
  // 正在把裁剪结果打包成 dataURL
  @State cropping: boolean = false

  aboutToAppear(): void {
    this.username = this.store.user?.username ?? ''
    this.displayName = this.store.user?.displayName ?? ''
    this.bio = this.store.user?.bio ?? ''
    this.avatarUrl = this.store.user?.avatarUrl ?? ''
  }

  aboutToDisappear(): void {
    this.releasePicked()
  }

  private releasePicked(): void {
    if (this.picked !== null) {
      try { this.picked.pixelMap.release() } catch (e) { /* ignore */ }
      this.picked = null
    }
  }

  build() {
    Column() {
      PageHeader({ store: this.store,
        title: appString(AppString.ProfileEdit, this.store.language) })
      Scroll() {
        Column({ space: AppSpacing.x4 }) {
          if (this.avatarUrl.length > 0) {
            Image(this.avatarUrl)
              .width(88).height(88).borderRadius(44).objectFit(ImageFit.Cover)
              .backgroundColor(AppColors.surfaceMuted)
          } else {
            Column() {
              AppIcon({ name: AppIconName.User, iconSize: 36, color: AppColors.brand })
            }
            .width(88).height(88).borderRadius(44)
            .backgroundColor(AppColors.brandSoft)
            .justifyContent(FlexAlign.Center)
          }
          AppButton({ label: appString(AppString.ChooseAvatar, this.store.language),
            icon: AppIconName.User, onTap: () => this.pickAvatar() })
          Text(this.username)
            .fontSize(16).fontColor(AppColors.textSecondary)
            .height(52).width('100%').textAlign(TextAlign.Start)
          TextInput({ placeholder: appString(AppString.DisplayName, this.store.language),
            text: this.displayName })
            .height(52).maxLength(40).backgroundColor(AppColors.surface)
            .border({ width: 1, color: AppColors.borderStrong })
            .borderRadius(AppRadii.control).onChange(value => this.displayName = value)
          TextInput({ placeholder: appString(AppString.Bio, this.store.language), text: this.bio })
            .height(96).maxLength(160).backgroundColor(AppColors.surface)
            .border({ width: 1, color: AppColors.borderStrong })
            .borderRadius(AppRadii.control).onChange(value => this.bio = value)
          AppButton({ label: this.store.busy
            ? appString(AppString.Saving, this.store.language)
            : appString(AppString.SaveProfile, this.store.language),
            icon: AppIconName.Check,
            onTap: () => this.store.updateProfile(this.displayName, this.bio, this.avatarUrl) })
        }
        .padding(AppSpacing.x4)
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
      }.layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%').height('100%')
    .bindSheet(this.editing, this.cropSheetBuilder(), {
      height: '66%',
      dragBar: true,
      maskColor: '#66000000',
      modalTransition: ModalTransition.DEFAULT,
      onDisappear: () => {
        if (this.picked !== null) {
          this.editing = false
          this.releasePicked()
        }
      }
    })
  }

  @Builder
  private cropSheetBuilder() {
    if (this.picked !== null) {
      AvatarCropEditor({
        sourceWidth: this.picked.width,
        sourceHeight: this.picked.height,
        pixelMap: this.picked.pixelMap,
        onCancel: () => {
          this.editing = false
          this.releasePicked()
        },
        onCropReady: (crop: CropRect) => {
          this.confirmCrop(crop)
        }
      })
    }
  }

  private async pickAvatar(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      this.releasePicked()
      const source = await pickAvatarPixelMap(context)
      if (source !== null) {
        this.picked = source
        this.editing = true
      }
    } catch (error) {
      this.store.showToast('头像处理失败，请重试', true)
    }
  }

  private async confirmCrop(crop: CropRect): Promise<void> {
    if (this.picked === null || this.cropping) return
    this.cropping = true
    try {
      const dataUrl = await cropPixelMapToAvatar(this.picked.pixelMap, crop)
      this.avatarUrl = dataUrl
      this.editing = false
      this.releasePicked()
    } catch (error) {
      this.store.showToast('头像处理失败，请重试', true)
    } finally {
      this.cropping = false
    }
  }
}
