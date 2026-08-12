import common from '@ohos.app.ability.common'
import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppButton, AppListRow, PageHeader } from '../design_system/Components'
import { AppIcon, AppIconName } from '../design_system/AppIcon'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { LegalDocument } from '../domain/Models'
import { pickAvatarDataUrl } from '../media/AvatarPicker'
import { appString, AppString } from '../localization/AppStrings'

@Component
export struct AccountSecurityPage {
  @ObjectLink store: AppStore
  @State currentPassword: string = ''
  @State newPassword: string = ''

  build() {
    Column() {
      PageHeader({ store: this.store, title: '账户与安全' })
      Column({ space: AppSpacing.x4 }) {
        AppListRow({ store: this.store, label: '登录邮箱',
          value: this.store.user?.email ?? '未登录' })
        PasswordInput({ label: '当前密码', value: this.currentPassword,
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
                  .onChange(() => this.selected = option)
                Text(this.label(option)).fontSize(16).fontColor(AppColors.text)
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
      List({ space: AppSpacing.x3 }) {
        ForEach(this.store.config?.legal ?? [], (document: LegalDocument) => {
          ListItem() {
            Column({ space: AppSpacing.x2 }) {
              Text(document.title).fontSize(18).fontWeight(FontWeight.Bold)
              Text(`版本 ${document.revision}`).fontColor(AppColors.textSecondary)
              Text(document.content).fontColor(AppColors.text)
            }
            .alignItems(HorizontalAlign.Start).padding(AppSpacing.x4)
            .backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
          }
        })
      }.padding(AppSpacing.x4).layoutWeight(1)
    }.width('100%').height('100%')
  }
}

@Component
export struct LegalDocumentPage {
  @ObjectLink store: AppStore
  @Prop type: string

  build() {
    Column() {
      PageHeader({ store: this.store, title: this.title() })
      Scroll() {
        Column({ space: AppSpacing.x3 }) {
          if (this.document() === undefined) {
            Text('当前 App 尚未配置该协议文档。').fontColor(AppColors.textSecondary)
          } else {
            Text(`版本 ${this.document()?.revision ?? ''}`).fontColor(AppColors.textSecondary)
            Text(this.document()?.content ?? '').fontColor(AppColors.text)
          }
        }.alignItems(HorizontalAlign.Start).padding(AppSpacing.x4)
      }.layoutWeight(1)
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
  build() {
    Column() {
      PageHeader({ store: this.store, title: '关于与版本' })
      Column() {
        AppListRow({ store: this.store, label: '产品',
          value: this.store.config?.brand.appName ?? 'MobileUI' })
        AppListRow({ store: this.store, label: '客户端版本', value: '1.0.0 (1)' })
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
  @State displayName: string = ''
  @State bio: string = ''
  @State avatarUrl: string = ''

  aboutToAppear(): void {
    this.displayName = this.store.user?.displayName ?? ''
    this.bio = this.store.user?.bio ?? ''
    this.avatarUrl = this.store.user?.avatarUrl ?? ''
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
          AppListRow({ store: this.store,
            label: appString(AppString.UsernameReadonly, this.store.language),
            value: `@${this.store.user?.username ?? ''}` })
          TextInput({ placeholder: appString(AppString.DisplayName, this.store.language),
            text: this.displayName })
            .height(52).maxLength(40).backgroundColor(AppColors.surface)
            .borderRadius(AppRadii.control).onChange(value => this.displayName = value)
          TextInput({ placeholder: appString(AppString.Bio, this.store.language), text: this.bio })
            .height(96).maxLength(160).backgroundColor(AppColors.surface)
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
    }.width('100%').height('100%')
  }

  private async pickAvatar(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    try {
      const dataUrl = await pickAvatarDataUrl(context)
      if (dataUrl !== null) this.avatarUrl = dataUrl
    } catch (error) {
      this.store.showToast('头像处理失败，请重试', true)
    }
  }
}
