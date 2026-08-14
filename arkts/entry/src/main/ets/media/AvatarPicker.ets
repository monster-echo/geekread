import photoAccessHelper from '@ohos.file.photoAccessHelper'
import image from '@ohos.multimedia.image'
import buffer from '@ohos.buffer'
import common from '@ohos.app.ability.common'
import { fileIo as fs } from '@kit.CoreFileKit'

// Picks an image from the gallery, scales it to ~512px and returns a JPEG data
// URL persisted via updateProfile (no separate upload endpoint, like RN).
// Native APIs must be verified on a HarmonyOS device/simulator.
export async function pickAvatarDataUrl(context: common.UIAbilityContext): Promise<string | null> {
  try {
    const options = new photoAccessHelper.PhotoSelectOptions()
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    options.maxSelectNumber = 1
    const picker = new photoAccessHelper.PhotoViewPicker()
    const selection = await picker.select(options)
    if (selection.photoUris.length === 0) return null
    const uri: string = selection.photoUris[0]
    console.info(`[geekread][avatar] picked uri=${uri}`)
    // PhotoViewPicker 返回的媒体库 uri 不能直接 createImageSource（仅支持沙箱路径），
    // 需先 fs.openSync 打开得到 fd 再据此创建（uri 为临时只读授权）。
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
    const source = image.createImageSource(file.fd)
    const pixelMap = await source.createPixelMap({
      desiredSize: { width: 512, height: 512 }
    })
    const packer = image.createImagePacker()
    const packed: ArrayBuffer = await packer.packToData(pixelMap, {
      format: 'image/jpeg',
      quality: 78
    })
    packer.release()
    pixelMap.release()
    source.release()
    fs.closeSync(file)
    const base64 = buffer.from(packed).toString('base64')
    return `data:image/jpeg;base64,${base64}`
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error)
    console.error(`[geekread][avatar] failed: ${msg}`)
    throw new Error(`avatar_pick_failed: ${msg}`)
  }
}
