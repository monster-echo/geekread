import { TargetLanguage } from '../domain/Models'

export function deriveTargetLanguage(locale: string): TargetLanguage | null {
  const l = locale.toLowerCase()
  if (l.startsWith('zh') && (l.includes('hant') || l.includes('tw') || l.includes('hk'))) return 'zh-Hant'
  if (l.startsWith('zh')) return 'zh-Hans'
  if (l.startsWith('ja')) return 'ja'
  if (l.startsWith('ko')) return 'ko'
  return null
}
