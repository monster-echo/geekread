import common from '@ohos.app.ability.common'
import { localStore } from '../data/LocalStore'
import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppButton, AppListRow, PageHeader } from '../design_system/Components'
import { AppIconName } from '../design_system/AppIcon'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'

@Component
export struct SettingsUtilityPage {
  @ObjectLink store: AppStore
  @Prop route: AppRoute
  @State title: string = ''
  @State body: string = ''
  @State cacheBytes: number = 0

  aboutToAppear(): void {
    this.cacheBytes = localStore.configBytes()
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: this.pageTitle() })
      if (this.route === AppRoute.Storage) {
        Column({ space: AppSpacing.x4 }) {
          AppListRow({ store: this.store, label: '运行时配置缓存',
            value: `${this.cacheBytes} B` })
          Text('只清理可再次下载的公开配置，不会删除登录凭证。')
            .fontColor(AppColors.textSecondary)
          AppButton({ label: '清理运行时缓存', icon: AppIconName.Trash,
            onTap: () => this.clearCache() })
        }.padding(AppSpacing.x4).layoutWeight(1)
      } else if (this.route === AppRoute.Permissions) {
        Column({ space: AppSpacing.x3 }) {
          AppListRow({ store: this.store, label: '相机与相册', value: '按需申请' })
          AppListRow({ store: this.store, label: '通知', value: '由系统管理' })
          AppListRow({ store: this.store, label: '麦克风', value: '按需申请' })
          Text('权限只会在相关功能使用时请求，可在 HarmonyOS 系统设置中随时修改。')
            .fontColor(AppColors.textSecondary)
          AppButton({ label: '打开系统设置', icon: AppIconName.Settings,
            onTap: () => this.openSystemSettings() })
        }.padding(AppSpacing.x4).layoutWeight(1)
      } else {
        Column({ space: AppSpacing.x4 }) {
          TextInput({ placeholder: '反馈标题', text: this.title })
            .height(52).backgroundColor(AppColors.surface).border({ width: 1, color: AppColors.borderStrong }).borderRadius(AppRadii.control)
            .onChange(value => this.title = value)
          TextInput({ placeholder: '告诉我们哪里可以做得更好', text: this.body })
            .height(160).backgroundColor(AppColors.surface).border({ width: 1, color: AppColors.borderStrong }).borderRadius(AppRadii.control)
            .onChange(value => this.body = value)
          AppButton({ label: this.store.busy ? '提交中…' : '提交意见反馈',
            icon: AppIconName.Check, onTap: () => this.submit() })
        }.padding(AppSpacing.x4).layoutWeight(1)
      }
    }.width('100%').height('100%')
  }

  private clearCache(): void {
    localStore.clearRuntimeCache()
    this.cacheBytes = 0
    this.store.showToast('运行时缓存已清理')
  }

  // Opens the HarmonyOS system settings app. The bundle name is best-effort
  // and must be verified on a device; failures surface a toast instead of crashing.
  private async openSystemSettings(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await context.startAbility({ bundleName: 'com.huawei.hmossettings' })
    } catch (error) {
      this.store.showToast('无法打开系统设置', true)
    }
  }

  private async submit(): Promise<void> {
    if (this.title.length < 4 || this.body.length < 4) {
      this.store.showToast('标题和内容至少需要 4 个字符', true)
      return
    }
    if (await this.store.submitFeedback(this.title, this.body)) {
      this.title = ''
      this.body = ''
    }
  }

  private pageTitle(): string {
    if (this.route === AppRoute.Storage) return '存储与缓存'
    if (this.route === AppRoute.Permissions) return '权限管理'
    return '帮助与反馈'
  }
}
