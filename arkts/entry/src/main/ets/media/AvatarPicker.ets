import photoAccessHelper from '@ohos.file.photoAccessHelper'
import image from '@ohos.multimedia.image'
import buffer from '@ohos.buffer'
import common from '@ohos.app.ability.common'
import { fileIo as fs } from '@kit.CoreFileKit'

// 头像选图 + 裁剪输出。流程：相册选图 → 解码可编辑 PixelMap（含各种格式/小图/URI 兜底）
// → 交给 AvatarCropEditor 裁剪 → 最终输出 512×512 的 JPEG data URL（经 updateProfile 持久化）。
// Native APIs 需在真机/模拟器上验证。
export interface AvatarSource {
  // 原始解码后的可编辑 PixelMap（保留原尺寸，供编辑器展示与裁剪；调用方负责 release）
  pixelMap: image.PixelMap
  // 原始尺寸
  width: number
  height: number
}

export const TARGET_AVATAR = 512 // 最终头像边长
const DECODE_HINT = 1024 // 解码提示尺寸（原图 ≥ 该值时用于加速解码）

/**
 * 从相册选图并解码为原始尺寸、可编辑的 PixelMap。
 * 返回 null 表示用户取消；否则返回 AvatarSource。
 * 针对已知失败模式做了兜底：
 *  - 小图：desiredSize 只在原图足够大时才使用（期望尺寸大于原图可能触发解码器拒绝）。
 *  - HEIC / HDR Vivid / 实况照片等：首次带 desiredSize 解码失败时，去掉 desiredSize 重试一次。
 *  - 媒体库 URI 打不开：fs.openSync 失败时改用 createImageSource(uri) 直接解码。
 */
export async function pickAvatarPixelMap(context: common.UIAbilityContext): Promise<AvatarSource | null> {
  const options = new photoAccessHelper.PhotoSelectOptions()
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
  options.maxSelectNumber = 1
  const picker = new photoAccessHelper.PhotoViewPicker()
  const selection = await picker.select(options)
  if (selection.photoUris.length === 0) return null
  const uri: string = selection.photoUris[0]
  console.info(`[geekread][avatar] picked uri=${uri}`)

  let source: image.ImageSource
  try {
    // PhotoViewPicker 返回的媒体库 uri 通常需先 fs.openSync 打开得到 fd 再创建（uri 为临时只读授权）。
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
    source = image.createImageSource(file.fd)
  } catch (e) {
    console.warn(`[geekread][avatar] openSync failed, fallback to createImageSource(uri): ${String(e)}`)
    source = image.createImageSource(uri)
  }

  let pixelMap: image.PixelMap
  const info = await source.getImageInfo()
  const srcW = info.size.width
  const srcH = info.size.height
  // 解码成可编辑 PixelMap，便于后续 crop/scale。
  const editableOpts: image.DecodingOptions = { editable: true }
  try {
    if (srcW < DECODE_HINT || srcH < DECODE_HINT) {
      // 原图较小：不再请求 desiredSize（避免"期望过大"报错），直接可编辑解码。
      pixelMap = await source.createPixelMap(editableOpts)
    } else {
      const sized: image.DecodingOptions = {
        editable: true,
        desiredSize: { width: DECODE_HINT, height: DECODE_HINT }
      }
      try {
        pixelMap = await source.createPixelMap(sized)
      } catch (e) {
        // 格式兜底：带尺寸解码失败时去尺寸重试。
        console.warn(`[geekread][avatar] desired decode failed, retry plain: ${String(e)}`)
        pixelMap = await source.createPixelMap(editableOpts)
      }
    }
  } catch (e) {
    source.release()
    throw new Error(`avatar_decode_failed: ${String(e)}`)
  }
  source.release()
  // 使用 decode 后 PixelMap 的实际尺寸作为编辑/裁切坐标系：
  // 当 desiredSize 把原图降至 1024 时，解码结果尺寸 ≠ 原图尺寸，坐标系必须用解码后的实际尺寸，
  // 否则裁剪区域可能越界导致 crop 失败。
  const pmInfo = pixelMap.getImageInfoSync()
  const pmW = pmInfo.size.width
  const pmH = pmInfo.size.height
  console.info(`[geekread][avatar] decoded editable ${pmW}x${pmH}`)
  return { pixelMap, width: pmW, height: pmH }
}

export interface CropRect {
  // 在原图像素坐标系下的正方形裁剪区域（x/y 由编辑器在合法范围内计算，保证不为负且不出界）
  x: number
  y: number
  size: number
}

// 编辑器二维点（ArkTS 禁止 untyped object literal，故用 class 承载）。
export class AvatarPoint {
  x: number = 0
  y: number = 0
  constructor(x: number, y: number) {
    this.x = x
    this.y = y
  }
}

// 编辑器展示几何的返回类型（ArkTS 禁止 untyped object literal）。
export class AvatarShownSize {
  w: number = 0
  h: number = 0
  constructor(w: number, h: number) {
    this.w = w
    this.h = h
  }
}

/**
 * 把原始 PixelMap 裁成正方形并缩放到 TARGET_AVATAR×TARGET_AVATAR，
 * 输出 JPEG data URL。crop 会在当前对象上就地修改，调用方无需额外 release。
 */
export async function cropPixelMapToAvatar(pixelMap: image.PixelMap, crop: CropRect): Promise<string> {
  if (pixelMap === null) throw new Error('avatar_empty_pixelmap')
  const infoValid = (crop.x >= 0 && crop.y >= 0 && crop.size > 0)
  if (!infoValid) throw new Error('avatar_invalid_crop')
  try {
    const region: image.Region = {
      size: { width: Math.floor(crop.size), height: Math.floor(crop.size) },
      x: Math.floor(crop.x),
      y: Math.floor(crop.y)
    }
    await pixelMap.crop(region)
    const scaleFactor = TARGET_AVATAR / crop.size
    await pixelMap.scale(scaleFactor, scaleFactor)
    const packer = image.createImagePacker()
    const packed: ArrayBuffer = await packer.packToData(pixelMap, {
      format: 'image/jpeg',
      quality: 78
    })
    packer.release()
    const base64 = buffer.from(packed).toString('base64')
    return `data:image/jpeg;base64,${base64}`
  } catch (e) {
    throw new Error(`avatar_crop_failed: ${String(e)}`)
  }
}
