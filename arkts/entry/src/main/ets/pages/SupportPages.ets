import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AsyncStatus } from '../state/AsyncState'
import { RemoteDataStore } from '../state/RemoteDataStore'
import { HelpArticle, SupportCategory, SupportMessage, SupportTicket } from '../domain/Models'
import { AppButton, AppListRow, PageHeader } from '../design_system/Components'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'

const TICKET_CATEGORIES: SupportCategory[] = [
  { id: 'technical', label: '技术问题' },
  { id: 'billing', label: '账单与会员' },
  { id: 'account', label: '账号问题' },
  { id: 'other', label: '其他' }
]
const FEEDBACK_CATEGORIES: SupportCategory[] = [
  { id: 'suggestion', label: '改进建议' },
  { id: 'experience', label: '使用体验' },
  { id: 'feature_request', label: '功能需求' },
  { id: 'other', label: '其他' }
]
const SEVERITIES: string[] = ['normal', 'high', 'urgent']
const RATINGS: number[] = [5, 4, 3, 2, 1]

function statusLabel(status: string): string {
  if (status === 'open' || status === 'waiting_for_support') return '处理中'
  if (status === 'resolved') return '已解决'
  if (status === 'closed') return '已关闭'
  return status.length > 0 ? status : '处理中'
}

function severityLabel(severity: string): string {
  if (severity === 'high') return '紧急'
  if (severity === 'urgent') return '十分紧急'
  return '一般'
}

function authorLabel(authorType: string): string {
  if (authorType === 'user') return '我'
  if (authorType === 'support') return '客服'
  return '系统'
}

@Component
export struct SupportHomePage {
  @ObjectLink store: AppStore
  @ObjectLink remote: RemoteDataStore

  aboutToAppear(): void {
    this.remote.loadHome()
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: '帮助与反馈' })
      Scroll() {
        Column({ space: AppSpacing.x5 }) {
          Column() {
            AppListRow({ store: this.store, label: '联系客服', route: AppRoute.NewSupportTicket })
            AppListRow({ store: this.store, label: '产品反馈', route: AppRoute.ProductFeedback })
          }
          .backgroundColor(AppColors.surface).borderRadius(AppRadii.card)

          Column({ space: AppSpacing.x2 }) {
            Text('我的工单').fontSize(13).fontColor(AppColors.textSecondary).width('100%')
            if (this.remote.ticketListState.status === AsyncStatus.Loading) {
              LoadingProgress().width(32).height(32)
            } else if (this.remote.ticketListState.status === AsyncStatus.Empty) {
              Text('暂无工单').fontColor(AppColors.textSecondary)
            } else if (this.remote.ticketListState.status === AsyncStatus.Success) {
              ForEach(this.remote.ticketListState.data ?? [], (ticket: SupportTicket) => {
                Row() {
                  Column({ space: AppSpacing.x1 }) {
                    Text(ticket.subject).fontSize(16).fontColor(AppColors.text)
                    Text(statusLabel(ticket.status)).fontSize(12).fontColor(AppColors.brand)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text('›').fontSize(20).fontColor(AppColors.textSecondary)
                }
                .width('100%').padding(AppSpacing.x4)
                .backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
                .onClick(() => {
                  this.remote.openTicket(ticket.id)
                    .then(() => this.store.navigate(AppRoute.SupportTicket))
                })
              }, (ticket: SupportTicket) => ticket.id)
            } else {
              Text(this.remote.ticketListState.message ?? '加载失败')
                .fontColor(AppColors.textSecondary)
            }
          }.width('100%')

          Column({ space: AppSpacing.x2 }) {
            Text('常见问题').fontSize(13).fontColor(AppColors.textSecondary).width('100%')
            if (this.remote.helpState.status === AsyncStatus.Success) {
              ForEach(this.remote.helpState.data ?? [], (article: HelpArticle) => {
                Column({ space: AppSpacing.x1 }) {
                  Text(article.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
                  Text(article.body).fontSize(13).fontColor(AppColors.textSecondary)
                }
                .alignItems(HorizontalAlign.Start).width('100%').padding(AppSpacing.x4)
                .backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
              }, (article: HelpArticle) => article.id)
            } else if (this.remote.helpState.status === AsyncStatus.Empty) {
              Text('暂无帮助文章').fontColor(AppColors.textSecondary)
            } else if (this.remote.helpState.status === AsyncStatus.Loading) {
              LoadingProgress().width(32).height(32)
            } else {
              Text(this.remote.helpState.message ?? '帮助内容加载失败')
                .fontColor(AppColors.textSecondary)
              AppButton({ label: '重试', onTap: () => this.remote.loadHome() })
            }
          }.width('100%')
        }.padding(AppSpacing.x4)
      }.layoutWeight(1)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
    }.width('100%').height('100%')
  }
}

@Component
export struct SupportTicketPage {
  @ObjectLink store: AppStore
  @ObjectLink remote: RemoteDataStore
  @State reply: string = ''

  build() {
    Column() {
      PageHeader({ store: this.store, title: '工单详情' })
      if (this.remote.ticketDetailState.status === AsyncStatus.Loading) {
        LoadingProgress().width(40).height(40).layoutWeight(1)
      } else if (this.remote.ticketDetailState.status === AsyncStatus.Success &&
        this.remote.ticketDetailState.data !== undefined) {
        Column() {
          Scroll() {
            Column({ space: AppSpacing.x3 }) {
              Column({ space: AppSpacing.x1 }) {
                Text(this.detail()!.subject).fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
                Text(`${statusLabel(this.detail()!.status)} · ${severityLabel(this.detail()!.severity)}`)
                  .fontSize(12).fontColor(AppColors.brand)
              }.alignItems(HorizontalAlign.Start).width('100%')
              ForEach(this.detail()!.messages, (message: SupportMessage) => {
                Column({ space: AppSpacing.x1 }) {
                  Text(authorLabel(message.authorType)).fontSize(12).fontColor(AppColors.textSecondary)
                  Text(message.body).fontSize(14).fontColor(AppColors.text)
                }
                .alignItems(HorizontalAlign.Start).width('100%').padding(AppSpacing.x3)
                .backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
              }, (message: SupportMessage) => message.id)
            }.padding(AppSpacing.x4)
          }.layoutWeight(1)
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring)
          Row({ space: AppSpacing.x2 }) {
            TextInput({ placeholder: '回复内容', text: this.reply })
              .layoutWeight(1).height(48).backgroundColor(AppColors.surface).border({ width: 1, color: AppColors.borderStrong }).borderRadius(AppRadii.control)
              .onChange(value => this.reply = value)
            Button('发送')
              .height(48)
              .backgroundColor(AppColors.brand).fontColor(AppColors.onBrand)
              .borderRadius(AppRadii.control)
              .onClick(() => this.send())
          }.width('100%').padding(AppSpacing.x4)
        }.width('100%').layoutWeight(1)
      } else {
        Column({ space: AppSpacing.x4 }) {
          Text(this.remote.ticketDetailState.message ?? '加载失败')
          AppButton({ label: '重试', onTap: () => this.store.back() })
        }.padding(AppSpacing.x6).justifyContent(FlexAlign.Center).layoutWeight(1)
      }
    }.width('100%').height('100%')
  }

  private detail() {
    return this.remote.ticketDetailState.data
  }

  private async send(): Promise<void> {
    if (this.reply.trim().length === 0) return
    if (await this.store.replyTicket(this.reply)) {
      this.reply = ''
    }
  }
}

@Component
export struct NewSupportTicketPage {
  @ObjectLink store: AppStore
  @State subject: string = ''
  @State message: string = ''
  @State category: string = TICKET_CATEGORIES[0].id
  @State severity: string = 'normal'

  build() {
    Column() {
      PageHeader({ store: this.store, title: '联系客服' })
      Scroll() {
        Column({ space: AppSpacing.x4 }) {
          TextInput({ placeholder: '主题（至少 4 字）', text: this.subject })
            .height(52).backgroundColor(AppColors.surface).border({ width: 1, color: AppColors.borderStrong }).borderRadius(AppRadii.control)
            .onChange(value => this.subject = value)
          TextArea({ placeholder: '描述你遇到的问题（至少 4 字）', text: this.message })
            .height(140).backgroundColor(AppColors.surface).border({ width: 1, color: AppColors.borderStrong }).borderRadius(AppRadii.control)
            .onChange(value => this.message = value)
          Text('类别').fontSize(13).fontColor(AppColors.textSecondary).width('100%')
          OptionRow({
            options: this.categories().map(c => c.id),
            labels: this.categories().map(c => c.label),
            selected: this.category,
            onSelect: value => this.category = value
          })
          Text('严重程度').fontSize(13).fontColor(AppColors.textSecondary).width('100%')
          OptionRow({
            options: SEVERITIES,
            labels: SEVERITIES.map(s => severityLabel(s)),
            selected: this.severity,
            onSelect: value => this.severity = value
          })
          AppButton({
            label: this.store.busy ? '提交中…' : '提交工单',
            onTap: () => this.submit()
          })
        }.padding(AppSpacing.x4)
      }.layoutWeight(1)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
    }.width('100%').height('100%')
  }

  private categories(): SupportCategory[] {
    return this.store.config?.support.categories ?? TICKET_CATEGORIES
  }

  private async submit(): Promise<void> {
    if (this.subject.trim().length < 4 || this.message.trim().length < 4) {
      this.store.showToast('主题和描述至少各 4 字', true)
      return
    }
    await this.store.createTicket(this.category, this.severity, this.subject, this.message)
  }
}

@Component
export struct ProductFeedbackPage {
  @ObjectLink store: AppStore
  @State title: string = ''
  @State body: string = ''
  @State category: string = FEEDBACK_CATEGORIES[0].id
  @State rating: number = 5

  build() {
    Column() {
      PageHeader({ store: this.store, title: '产品反馈' })
      Scroll() {
        Column({ space: AppSpacing.x4 }) {
          TextInput({ placeholder: '标题（至少 4 字）', text: this.title })
            .height(52).backgroundColor(AppColors.surface).border({ width: 1, color: AppColors.borderStrong }).borderRadius(AppRadii.control)
            .onChange(value => this.title = value)
          TextArea({ placeholder: '你的反馈（至少 4 字）', text: this.body })
            .height(160).backgroundColor(AppColors.surface).border({ width: 1, color: AppColors.borderStrong }).borderRadius(AppRadii.control)
            .onChange(value => this.body = value)
          Text('类别').fontSize(13).fontColor(AppColors.textSecondary).width('100%')
          OptionRow({
            options: FEEDBACK_CATEGORIES.map(c => c.id),
            labels: FEEDBACK_CATEGORIES.map(c => c.label),
            selected: this.category,
            onSelect: value => this.category = value
          })
          Text('评分').fontSize(13).fontColor(AppColors.textSecondary).width('100%')
          OptionRow({
            options: RATINGS.map(r => String(r)),
            labels: RATINGS.map(r => `${r} 星`),
            selected: String(this.rating),
            onSelect: value => this.rating = Number(value)
          })
          AppButton({
            label: this.store.busy ? '提交中…' : '提交反馈',
            onTap: () => this.submit()
          })
        }.padding(AppSpacing.x4)
      }.layoutWeight(1)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
    }.width('100%').height('100%')
  }

  private async submit(): Promise<void> {
    if (this.title.trim().length < 4 || this.body.trim().length < 4) {
      this.store.showToast('标题和反馈至少各 4 字', true)
      return
    }
    if (await this.store.submitFeedback(this.title, this.body, this.category, this.rating)) {
      this.store.back()
    }
  }
}

@Component
struct OptionRow {
  @Prop options: string[]
  @Prop labels: string[]
  @Prop selected: string
  onSelect: (value: string) => void = () => {}

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.options, (option: string, index: number) => {
        Button(this.labels[index])
          .height(40)
          .margin({ right: AppSpacing.x2, bottom: AppSpacing.x2 })
          .fontColor(option === this.selected ? AppColors.surface : AppColors.text)
          .backgroundColor(option === this.selected ? AppColors.brand : AppColors.surface)
          .borderRadius(AppRadii.control)
          .onClick(() => this.onSelect(option))
      }, (option: string) => option)
    }.width('100%')
  }
}
