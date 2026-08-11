export type TargetLanguage = 'en' | 'ja' | 'ko' | 'zh-Hans' | 'zh-Hant'

export interface HNItem {
  id: number
  type?: string
  by?: string
  time?: number
  title?: string
  url?: string
  text?: string
  score?: number
  descendants?: number
  kids?: number[]
  parent?: number
  deleted?: boolean
  dead?: boolean
}

export interface Story {
  id: number
  title: string
  by: string
  url?: string
  text?: string
  score: number
  commentsCount: number
  time: number
  kids: number[]
}

export interface Comment {
  id: number
  by: string
  text: string
  time: number
  parentId: number
  kids: number[]
  deleted?: boolean
  dead?: boolean
}

export function toStory(item: HNItem | null): Story | null {
  if (item === null || !item.id) return null
  const s: Story = {
    id: item.id,
    title: item.title ?? '',
    by: item.by ?? '',
    score: item.score ?? 0,
    commentsCount: item.descendants ?? 0,
    time: item.time ?? 0,
    kids: item.kids ?? [],
  }
  if (item.url) s.url = item.url
  if (item.text) s.text = item.text
  return s
}

export function toComment(item: HNItem | null): Comment | null {
  if (item === null || !item.id) return null
  const c: Comment = {
    id: item.id,
    by: item.by ?? '',
    text: item.text ?? '',
    time: item.time ?? 0,
    parentId: item.parent ?? 0,
    kids: item.kids ?? [],
  }
  if (item.deleted) c.deleted = item.deleted
  if (item.dead) c.dead = item.dead
  return c
}
