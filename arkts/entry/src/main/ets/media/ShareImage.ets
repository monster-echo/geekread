import { image } from '@kit.ImageKit'
import { fileIo as fs, fileUri } from '@kit.CoreFileKit'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'

/**
 * 把 PixelMap 打包成 PNG 写入沙箱缓存目录，返回 file:// URI。
 * 复用 media/AvatarPicker.ets 的 ImagePacker 模式。
 */
export async function savePixelMapToCache(pixelMap: image.PixelMap, ctx: common.UIAbilityContext): Promise<string> {
  const packer = image.createImagePacker()
  const bytes: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 })
  packer.release()
  pixelMap.release()

  const path = `${ctx.cacheDir}/share_card_${Date.now()}.png`
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
  fs.writeSync(file.fd, bytes)
  fs.closeSync(file)
  return fileUri.getUriFromPath(path)
}

/** 用系统分享面板分享一张图片（file:// URI）。 */
export async function shareImage(uri: string, ctx: common.UIAbilityContext): Promise<void> {
  const data = new systemShare.SharedData({ utd: utd.UniformDataType.PNG, uri: uri })
  const controller = new systemShare.ShareController(data)
  await controller.show(ctx, { previewMode: systemShare.SharePreviewMode.DETAIL })
}
