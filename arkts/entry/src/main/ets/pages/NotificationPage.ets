import { NotificationView } from '../domain/Models'
import { AppStore } from '../state/AppStore'
import { AsyncStatus } from '../state/AsyncState'
import { RemoteDataStore } from '../state/RemoteDataStore'
import { AppButton, PageHeader } from '../design_system/Components'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'

@Component
export struct NotificationPage {
  @ObjectLink store: AppStore
  @ObjectLink remote: RemoteDataStore

  aboutToAppear(): void {
    this.remote.loadNotifications()
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: '通知中心' })
      if (this.remote.notificationState.status === AsyncStatus.Loading) {
        LoadingProgress().width(40).height(40).layoutWeight(1)
      } else if (this.remote.notificationState.status === AsyncStatus.Empty) {
        Text('暂无通知').fontColor(AppColors.textSecondary).layoutWeight(1)
      } else if (this.remote.notificationState.status === AsyncStatus.Success) {
        Row() {
          Text(`共 ${this.totalCount()} 条 · ${this.unreadCount()} 条未读`)
            .fontColor(AppColors.textSecondary).fontSize(12).layoutWeight(1)
          Button('全部已读').backgroundColor(Color.Transparent).fontColor(AppColors.brand)
            .enabled(this.unreadCount() > 0)
            .onClick(() => this.remote.markAllNotificationsRead())
        }.padding({ left: AppSpacing.x4, right: AppSpacing.x4 }).width('100%')
        List({ space: AppSpacing.x3 }) {
          ForEach(this.remote.notificationState.data ?? [], (item: NotificationView) => {
            ListItem() {
              Column({ space: AppSpacing.x2 }) {
                Text(item.title).fontSize(18).fontWeight(FontWeight.Bold)
                Text(item.body).fontColor(AppColors.textSecondary)
                Text(item.readAt === null ? '未读' : '已读').fontColor(AppColors.brand)
                Row({ space: AppSpacing.x3 }) {
                  if (item.readAt === null) {
                    Button('标记已读')
                      .height(44)
                      .backgroundColor(AppColors.brandSoft)
                      .fontColor(AppColors.brand)
                      .onClick(() => this.remote.markNotificationRead(item.id))
                  }
                  Button('删除')
                    .height(44)
                    .backgroundColor(Color.Transparent)
                    .fontColor(AppColors.error)
                    .onClick(() => this.confirmDelete(item.id))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .padding(AppSpacing.x4)
              .backgroundColor(AppColors.surface)
              .borderRadius(AppRadii.card)
            }
            .onClick(() => this.open(item))
          })
        }.padding(AppSpacing.x4).layoutWeight(1)
      } else {
        Column({ space: AppSpacing.x4 }) {
          Text(this.remote.notificationState.message ?? '加载失败')
          AppButton({ label: '重试', onTap: () => this.remote.loadNotifications() })
        }.padding(AppSpacing.x6).justifyContent(FlexAlign.Center).layoutWeight(1)
      }
    }.width('100%').height('100%')
  }

  private confirmDelete(id: string): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除这条通知？',
      message: '删除后不会再次显示。',
      buttons: [
        { text: '取消', color: '#667085' },
        { text: '删除', color: '#D24B4B' }
      ]
    }).then(result => {
      if (result.index === 1) this.remote.deleteNotification(id)
    })
  }

  private totalCount(): number {
    return this.remote.notificationState.data?.length ?? 0
  }

  private unreadCount(): number {
    return this.remote.notificationState.data?.filter(item => item.readAt === null).length ?? 0
  }

  private async open(item: NotificationView): Promise<void> {
    if (item.readAt === null) {
      await this.remote.markNotificationRead(item.id)
    }
    this.store.navigateByName(item.route)
  }
}


