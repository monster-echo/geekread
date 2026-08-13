import { UIAbility, Want, errorManager } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { AbilityConstant } from '@kit.AbilityKit'
import { EntryIntent, entryIntentInbox, routeNameFromWant } from '../navigation/EntryIntent'
import { telemetry } from '../telemetry/Telemetry'

export default class EntryAbility extends UIAbility {
  private enteredForeground: boolean = false

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    entryIntentInbox.publish(new EntryIntent(routeNameFromWant(want), true))
    // 全局 JS 异常捕获：记录到 console + 上报 telemetry（app_error）
    errorManager.on('globalErrorOccurred', (error: errorManager.GlobalError) => {
      console.error('[geekread][uncaught]', error.message, error.stack)
      telemetry.report(new Error(`uncaught: ${error.message ?? 'unknown'}`))
    })
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index')
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    entryIntentInbox.publish(new EntryIntent(routeNameFromWant(want), false))
  }

  onForeground(): void {
    if (this.enteredForeground) entryIntentInbox.publishResume()
    this.enteredForeground = true
  }
}
