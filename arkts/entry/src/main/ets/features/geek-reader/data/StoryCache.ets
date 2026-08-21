import { localStore } from '../../../data/LocalStore'
import { Story } from '../domain/Models'

const KEY_PREFIX: string = 'reader.cache.stories.'

/** 读缓存列表（缺失/损坏返回 null）。 */
export function readStories(type: string): Story[] | null {
  return localStore.readJson<Story[]>(KEY_PREFIX + type)
}

/** 写缓存列表（成功拉取后调用，供冷启动秒开）。 */
export function saveStories(type: string, stories: Story[]): void {
  localStore.saveJson(KEY_PREFIX + type, stories)
}
