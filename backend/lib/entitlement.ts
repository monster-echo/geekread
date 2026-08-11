import { createHmac, timingSafeEqual } from 'node:crypto';

export type EntitlementClaims = { exp: number; [k: string]: unknown };

export function signEntitlement(claims: EntitlementClaims): string {
  const secret = process.env.ENTITLEMENT_SIGNING_SECRET ?? '';
  if (!secret) throw new Error('entitlement_secret_not_configured');
  const payload = Buffer.from(JSON.stringify(claims)).toString('base64url');
  const signature = createHmac('sha256', secret).update(payload).digest('base64url');
  return `${payload}.${signature}`;
}

export function hasProEntitlement(token: string): boolean {
  const secret = process.env.ENTITLEMENT_SIGNING_SECRET ?? '';
  if (!token || !secret) return false;
  const [payload, signature] = token.split('.');
  if (!payload || !signature) return false;
  const expected = createHmac('sha256', secret).update(payload).digest('base64url');
  if (signature.length !== expected.length
    || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return false;
  try {
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString()) as { exp?: number };
    return Number(decoded.exp ?? 0) > Date.now() / 1000;
  } catch {
    return false;
  }
}
