import type { HNItem, Story, TargetLanguage } from '../domain/models';
import { toStory } from '../domain/models';

const BASE = () => {
  const url = process.env.EXPO_PUBLIC_GEEKREAD_BACKEND_URL?.trim();
  if (!url) throw new Error('EXPO_PUBLIC_GEEKREAD_BACKEND_URL 未配置');
  return url.replace(/\/$/, '');
};

// 默认 reader 懒加载 storage（避免 node 测试环境静态拉入 react-native/expo-secure-store）。
// 生产首次调用动态 import；测试用 setInstallIdReader/setTokenReader 覆盖。
let installIdReader: () => Promise<string> = async () => {
  const { readAnonymousId } = await import('../../../data/storage');
  return readAnonymousId();
};
let tokenReader: () => Promise<string | null> = async () => {
  const { readSessionToken } = await import('../../../data/storage');
  return readSessionToken();
};

export function setInstallIdReader(r: () => Promise<string>) { installIdReader = r; }
export function setTokenReader(r: () => Promise<string | null>) { tokenReader = r; }

async function authHeaders(): Promise<Record<string, string>> {
  const installId = await installIdReader();
  const token = await tokenReader();
  const h: Record<string, string> = { 'x-install-id': installId };
  if (token) h['authorization'] = `Bearer ${token}`;
  return h;
}

async function send(path: string, init?: RequestInit): Promise<Response> {
  const res = await fetch(`${BASE()}${path}`, init);
  if (!res.ok) throw new Error(`geekreader_${res.status}`);
  return res;
}

export async function fetchStories(type: 'top' | 'latest'): Promise<{ ids: number[]; cached: boolean; stale: boolean }> {
  const res = await send(`/api/reader/stories?type=${type}`, { headers: await authHeaders() });
  return res.json();
}

export async function fetchItems(ids: number[]): Promise<{ items: (HNItem | null)[]; cached: boolean; stale: boolean }> {
  const res = await send('/api/reader/items', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(await authHeaders()) },
    body: JSON.stringify({ ids }),
  });
  return res.json();
}

export type TranslateRequest = {
  targetLanguage: TargetLanguage;
  entries: { key: string; text: string }[];
};

export type TranslateResponse = {
  results: { key: string; translation?: string; cached?: boolean; error?: string }[];
  remainingTranslations?: number;
};

export async function translateBatch(req: TranslateRequest): Promise<TranslateResponse> {
  const res = await send('/api/translate', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(await authHeaders()) },
    body: JSON.stringify(req),
  });
  return res.json();
}

export async function fetchStoriesResolved(ids: number[]): Promise<Story[]> {
  const { items } = await fetchItems(ids);
  return items.map(toStory).filter((s): s is Story => s !== null);
}
