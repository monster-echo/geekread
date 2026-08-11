import { UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { AbilityConstant } from '@kit.AbilityKit'
import { EntryIntent, entryIntentInbox, routeNameFromWant } from '../navigation/EntryIntent'

export default class EntryAbility extends UIAbility {
  private enteredForeground: boolean = false

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    entryIntentInbox.publish(new EntryIntent(routeNameFromWant(want), true))
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
