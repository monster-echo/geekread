import photoAccessHelper from '@ohos.file.photoAccessHelper'
import image from '@ohos.multimedia.image'
import buffer from '@ohos.buffer'
import common from '@ohos.app.ability.common'

// Picks an image from the gallery, scales it to ~512px and returns a JPEG data
// URL persisted via updateProfile (no separate upload endpoint, like RN).
// Native APIs must be verified on a HarmonyOS device/simulator.
export async function pickAvatarDataUrl(context: common.UIAbilityContext): Promise<string | null> {
  const options = new photoAccessHelper.PhotoSelectOptions()
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
  options.maxSelectNumber = 1
  const picker = new photoAccessHelper.PhotoViewPicker()
  const selection = await picker.select(options)
  if (selection.photoUris.length === 0) return null
  const uri: string = selection.photoUris[0]
  const source = image.createImageSource(uri)
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
  const base64 = buffer.from(packed).toString('base64')
  return `data:image/jpeg;base64,${base64}`
}
