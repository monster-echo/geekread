import image from '@ohos.multimedia.image'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { localized } from '../localization/AppStrings'
import { AvatarPoint, AvatarShownSize, CropRect } from './AvatarPicker'

// 头像裁剪：作为底部弹窗（bindSheet，约 2/3 高度）的内容。照片铺满圆形裁剪区，
// 拖动定位、双指捏合缩放，底部「取消 / 使用此裁剪」。
// 尺寸直接读 PixelMap 的 getImageInfoSync()，确保显示比例与裁剪坐标一致（避免变形）。
// 拖动以手势起点为基准 1:1 跟手（不逐帧累加），因此无惯性、定位准确。
// 注意：PixelMap 为 SDK 对象，不能作为 @State/@Prop，故用普通成员由父组件在挂载时注入。

const CROP = 300 // 裁剪区边长（vp）
const MIN_ZOOM = 1
const MAX_ZOOM = 3
const PAN_DISTANCE = 12 // 拖动触发阈值（vp），越大越不易抖动
// 拖动跟手系数：1.0 = 图片与手指 1:1 精确跟手。保持 1:1 才能定位准确；
// 若希望图片比手指慢一点，可调低（如 0.7），但会略滞后。
const DRAG_GAIN = 1.0

@Component
export struct AvatarCropEditor {
  sourceWidth: number = 0
  sourceHeight: number = 0
  pixelMap: image.PixelMap | null = null
  onCancel: () => void = () => {}
  onCropReady: (crop: CropRect) => void = () => {}

  @State zoom: number = 1
  @State offsetX: number = 0
  @State offsetY: number = 0
  private liveZoom: number = 1
  // 拖动起始时的展示偏移（PanGesture 的 offsetX/Y 为相对手势起点的累积位移，
  // 必须以手势起点为基准重算，否则逐事件累加会「越跟越快/滑过头」，表现为惯性且定位不准）
  private startX: number = 0
  private startY: number = 0
  // 从 PixelMap 读取的实际尺寸（与裁剪坐标统一，避免变形）
  private pmW: number = 0
  private pmH: number = 0
  private pmReady: boolean = false

  // 尺寸加载：优先读 PixelMap 的实际尺寸，兜底用父组件传入的 sourceWidth/Height。
  private loadSize(): void {
    if (this.pmReady) return
    if (this.pixelMap !== null) {
      try {
        const info = this.pixelMap.getImageInfoSync()
        const size = info.size
        if (size.width > 0 && size.height > 0) {
          this.pmW = size.width
          this.pmH = size.height
          this.pmReady = true
          return
        }
      } catch (e) {
        // fallthrough
      }
    }
    this.pmW = this.sourceWidth
    this.pmH = this.sourceHeight
    this.pmReady = true
  }

  private srcW(): number {
    this.loadSize()
    return this.pmW
  }

  private srcH(): number {
    this.loadSize()
    return this.pmH
  }

  private computeShown(zoom: number): AvatarShownSize {
    const w = this.srcW()
    const h = this.srcH()
    const base = CROP / Math.min(w, h)
    // 取整（round）避免亚像素尺寸导致的非等比缩放宽高比漂移/变形。
    return new AvatarShownSize(
      Math.max(1, Math.round(w * base * zoom)),
      Math.max(1, Math.round(h * base * zoom))
    )
  }

  private clampOffset(ox: number, oy: number, zoom: number): AvatarPoint {
    const shown = this.computeShown(zoom)
    const maxX = Math.max(0, (shown.w - CROP) / 2)
    const maxY = Math.max(0, (shown.h - CROP) / 2)
    return new AvatarPoint(Math.max(-maxX, Math.min(maxX, ox)), Math.max(-maxY, Math.min(maxY, oy)))
  }

  private setZoom(next: number): void {
    const z = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, next))
    const clamped = this.clampOffset(this.offsetX, this.offsetY, z)
    this.liveZoom = z
    this.zoom = z
    this.offsetX = clamped.x
    this.offsetY = clamped.y
  }

  private panStart(): void {
    this.loadSize()
    // 记录手势起点对应的展示偏移作为基准
    this.startX = this.offsetX
    this.startY = this.offsetY
  }

  private panMove(dx: number, dy: number): void {
    // dx/dy 是相对手势起点的累积位移（单位 vp）。始终从起点基准推导，避免逐帧累加漂移。
    const clamped = this.clampOffset(this.startX + dx * DRAG_GAIN, this.startY + dy * DRAG_GAIN, this.zoom)
    this.offsetX = clamped.x
    this.offsetY = clamped.y
  }

  private pinchStart(): void {
    this.loadSize()
    this.liveZoom = this.zoom
  }

  private pinchUpdate(gestureScale: number): void {
    this.setZoom(this.liveZoom * gestureScale)
  }

  private confirm(): void {
    this.loadSize()
    const w = this.pmW
    const h = this.pmH
    const shown = this.computeShown(this.zoom)
    const imageLeft = (CROP - shown.w) / 2 + this.offsetX
    const imageTop = (CROP - shown.h) / 2 + this.offsetY
    const ratio = w / shown.w
    const srcSize = Math.min(CROP * ratio, Math.min(w, h))
    const srcX = -imageLeft * ratio
    const srcY = -imageTop * ratio
    const maxX = w - srcSize
    const maxY = h - srcSize
    const crop: CropRect = {
      x: Math.min(Math.max(0, srcX), Math.max(0, maxX)),
      y: Math.min(Math.max(0, srcY), Math.max(0, maxY)),
      size: srcSize
    }
    this.onCropReady(crop)
  }

  build() {
    Column() {
      Text(localized('裁剪头像', 'Crop avatar', 'zh-CN'))
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
        .margin({ top: AppSpacing.x4, bottom: AppSpacing.x2 })
      Text(localized('拖动调整位置，双指捏合缩放', 'Drag to move, pinch to zoom.', 'zh-CN'))
        .fontSize(13).fontColor(AppColors.textSecondary)

      // 裁剪区
      Column() {
        Stack() {
          if (this.pixelMap !== null) {
            Image(this.pixelMap as image.PixelMap)
              .width(this.computeShown(this.zoom).w)
              .height(this.computeShown(this.zoom).h)
              // 显示框宽高比 = 源图宽高比（经 round 对齐），Fill 不会变形。
              .objectFit(ImageFit.Fill)
              .translate({ x: this.offsetX, y: this.offsetY })
          }
          Circle()
            .width(CROP).height(CROP)
            .fill(Color.Transparent)
            .stroke(AppColors.brand)
            .strokeWidth(3)
        }
        .width(CROP).height(CROP)
        .clip(true)
        .borderRadius(CROP / 2)
        .backgroundColor(AppColors.surface)
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PanGesture({ fingers: 1, distance: PAN_DISTANCE })
              .onActionStart(() => this.panStart())
              .onActionUpdate((event: GestureEvent) => this.panMove(event.offsetX, event.offsetY)),
            PinchGesture({ fingers: 2 })
              .onActionStart(() => this.pinchStart())
              .onActionUpdate((event: GestureEvent) => this.pinchUpdate(event.scale))
          )
        )
      }
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      // 底部操作按钮
      Row({ space: AppSpacing.x4 }) {
        Button({ type: ButtonType.Normal }) {
          Text(localized('取消', 'Cancel', 'zh-CN'))
            .fontSize(16).fontColor(AppColors.text)
        }
        .height(52)
        .layoutWeight(1)
        .backgroundColor(AppColors.surface)
        .borderRadius(AppRadii.control)
        .border({ width: 1, color: AppColors.border })
        .onClick(() => this.onCancel())

        Button({ type: ButtonType.Normal }) {
          Text(localized('使用此裁剪', 'Done', 'zh-CN'))
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppColors.onBrand)
        }
        .height(52)
        .layoutWeight(1)
        .backgroundColor(AppColors.brand)
        .borderRadius(AppRadii.control)
        .onClick(() => this.confirm())
      }
      .width('100%')
      .padding({ left: AppSpacing.x4, right: AppSpacing.x4, bottom: AppSpacing.x4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.surface)
    .border({ width: { top: 1 }, color: AppColors.border })
  }
}
