// 极客译读 Pro 权益令牌：从 MobileStarter server（EXPO_PUBLIC_API_URL）拉取
// HMAC-signed entitlement JWT，缓存到到期前 60s。GeekReaderApiClient 用它作 Bearer
// 发给极客译读后端（与 MobileStarter 的 session token 区分开）。

const API_URL = (): string | undefined => process.env.EXPO_PUBLIC_API_URL?.trim();
const APP_ID = (): string => process.env.EXPO_PUBLIC_APP_ID?.trim() ?? '';
const APP_ENV = (): string => process.env.EXPO_PUBLIC_APP_ENVIRONMENT?.trim() ?? 'development';

// 懒加载 storage，避免 node 测试环境静态拉入 react-native。
let installIdReader: () => Promise<string> = async () => {
  const { readAnonymousId } = await import('../../../data/storage');
  return readAnonymousId();
};
let sessionTokenReader: () => Promise<string | null> = async () => {
  const { readSessionToken } = await import('../../../data/storage');
  return readSessionToken();
};

export function setInstallIdReader(r: () => Promise<string>) { installIdReader = r; }
export function setSessionTokenReader(r: () => Promise<string | null>) { sessionTokenReader = r; }

type Cached = { token: string | null; exp: number } | null;
let cached: Cached = null;

export function clearEntitlementCache(): void { cached = null; }

export async function getEntitlementToken(): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - now > 60) return cached.token;
  const base = API_URL();
  const session = await sessionTokenReader();
  if (!base || !session) return null; // 未登录或未配置 → 无 entitlement
  const headers: Record<string, string> = {
    authorization: `Bearer ${session}`,
    'x-app-id': APP_ID(),
    'x-app-environment': APP_ENV(),
  };
  const iid = await installIdReader();
  if (iid) headers['x-installation-id'] = iid;
  try {
    const res = await fetch(`${base.replace(/\/$/, '')}/api/v1/me/entitlement`, { method: 'POST', headers });
    if (!res.ok) return cached?.token ?? null;
    const body = (await res.json()) as { token: string | null; expiresAt: number | null };
    cached = { token: body.token, exp: body.expiresAt ?? now };
    return body.token;
  } catch {
    return cached?.token ?? null;
  }
}
