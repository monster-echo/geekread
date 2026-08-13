// 缓存预热脚本（cron 每小时 docker exec geekread-backend node /app/warm-cache.cjs）
// 拉 HN 热门/最新列表 + 前 30 篇文章，写入与后端一致的 redis 缓存，用户首启即命中。
const { createClient } = require('redis')

const BASE = process.env.HACKER_NEWS_API_URL?.trim() || 'https://hacker-news.firebaseio.com/v0'
const REDIS_URL = process.env.REDIS_URL?.trim() || 'redis://redis:6379'

async function main() {
  const redis = createClient({
    url: REDIS_URL,
    socket: { connectTimeout: 4000, reconnectStrategy: false },
  })
  redis.on('error', () => {})
  await redis.connect()

  const setJson = async (key, value, freshMs, staleMs) => {
    await redis.set(
      `geekread:data-cache:${key}`,
      JSON.stringify({ freshUntil: Date.now() + freshMs, value }),
      { EX: Math.floor(staleMs / 1000) },
    )
  }
  const fetchJson = async (path) => {
    try {
      const r = await fetch(`${BASE}${path}`, { signal: AbortSignal.timeout(8000) })
      return r.ok ? r.json() : null
    } catch { return null }
  }

  const [top, latest] = await Promise.all([fetchJson('/topstories.json'), fetchJson('/newstories.json')])
  if (Array.isArray(top)) await setJson('hn:stories:top', top, 60_000, 600_000)
  if (Array.isArray(latest)) await setJson('hn:stories:latest', latest, 60_000, 600_000)

  const ids = [...new Set([...(top || []).slice(0, 30), ...(latest || []).slice(0, 30)])].slice(0, 30)
  await Promise.all(ids.map(async (id) => {
    try {
      const item = await fetchJson(`/item/${id}.json`)
      if (item) await setJson(`hn:item:${id}`, item, 300_000, 3_600_000)
    } catch {}
  }))

  await redis.quit()
  console.log(`[warm-cache] done: ${ids.length} items`)
}

main().catch((e) => { console.error('[warm-cache] failed:', e.message); process.exit(1) })
