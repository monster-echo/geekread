export type HNItem = {
  id: number;
  type?: string;
  by?: string;
  time?: number;
  title?: string;
  url?: string;
  text?: string;
  score?: number;
  descendants?: number;
  kids?: number[];
  parent?: number;
  deleted?: boolean;
  dead?: boolean;
};

export type TargetLanguage = 'en' | 'ja' | 'ko' | 'zh-Hans' | 'zh-Hant';

export type Story = {
  id: number;
  title: string;
  by: string;
  url?: string;
  text?: string;
  score: number;
  commentsCount: number;
  time: number;
  kids: number[];
};

export type Comment = {
  id: number;
  by: string;
  text: string;
  time: number;
  parentId: number;
  kids: number[];
  deleted?: boolean;
  dead?: boolean;
};

export function toStory(item: HNItem | null): Story | null {
  if (!item || !item.id) return null;
  return {
    id: item.id,
    title: item.title ?? '',
    by: item.by ?? '',
    url: item.url,
    text: item.text,
    score: item.score ?? 0,
    commentsCount: item.descendants ?? 0,
    time: item.time ?? 0,
    kids: item.kids ?? [],
  };
}

export function toComment(item: HNItem | null): Comment | null {
  if (!item || !item.id) return null;
  return {
    id: item.id,
    by: item.by ?? '',
    text: item.text ?? '',
    time: item.time ?? 0,
    parentId: item.parent ?? 0,
    kids: item.kids ?? [],
    deleted: item.deleted,
    dead: item.dead,
  };
}
