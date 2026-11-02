// backend/app/api/reader/moderation/route.ts
//
// 内容审核管理接口（运维用，需 OPS_TOKEN；未配置则回退 WARM_CACHE_TOKEN，两者都未配置则拒绝）。
//
// GET  /api/reader/moderation?token=...&view=reports|blocks&limit=100
//      → 举报列表（含 reviewedAt）与黑名单
// POST /api/reader/moderation?token=...
//      { action: "block", kind: "story"|"comment", targetId, reason?, reportId? }
//      { action: "unblock", kind, targetId }
//      { action: "resolve", reportId, decision: "block"|"dismiss", reason? }
//
// 处置动作会同步清理被下架内容的翻译/摘要缓存，避免“已下架但仍能从缓存读到违规译文”。

import { errorResponse, json } from '../../../../lib/http';
import { addBlock, isBlockKind, listBlocks, removeBlock } from '../../../../lib/blocklist';
import { readItems } from '../../../../lib/hn-store';
import { getReport, listReports, markReportReviewed } from '../../../../lib/report-store';
import { purgeSummariesByStory, purgeTranslationsBySource } from '../../../../lib/cache-store';

function expectedToken(): string {
  return (process.env.OPS_TOKEN?.trim() || process.env.WARM_CACHE_TOKEN?.trim() || '');
}

function authorized(request: Request): boolean {
  const expected = expectedToken();
  if (!expected) return false;
  const url = new URL(request.url);
  const bearer = /^Bearer\s+(.+)$/i.exec(request.headers.get('authorization') ?? '')?.[1]?.trim();
  const token = url.searchParams.get('token')?.trim() || bearer || '';
  return token.length > 0 && token === expected;
}

function limitOf(request: Request): number {
  const raw = Number(new URL(request.url).searchParams.get('limit'));
  if (!Number.isFinite(raw) || raw <= 0) return 100;
  return Math.min(Math.floor(raw), 500);
}

/** 读取被处置 item 的原文（用于清理翻译缓存）；未缓存/不存在时返回空。 */
async function sourcesOf(kind: 'story' | 'comment', targetId: number): Promise<string[]> {
  try {
    const row = (await readItems([targetId])).get(targetId)?.raw;
    if (!row) return [];
    const texts: string[] = [];
    if (kind === 'story' && typeof row.title === 'string') texts.push(row.title);
    if (typeof row.text === 'string') texts.push(row.text);
    return texts;
  } catch {
    return [];
  }
}

export async function GET(request: Request): Promise<Response> {
  if (!authorized(request)) return errorResponse('forbidden', 403);
  const view = new URL(request.url).searchParams.get('view');
  const limit = limitOf(request);
  try {
    if (view === 'reports') return json({ reports: await listReports(limit) });
    if (view === 'blocks') return json({ blocks: await listBlocks(limit) });
    const [reports, blocks] = await Promise.all([listReports(limit), listBlocks(limit)]);
    return json({ reports, blocks });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, 503);
  }
}

type PostBody = {
  action?: unknown;
  kind?: unknown;
  targetId?: unknown;
  reason?: unknown;
  reportId?: unknown;
  decision?: unknown;
  source?: unknown;
};

export async function POST(request: Request): Promise<Response> {
  if (!authorized(request)) return errorResponse('forbidden', 403);

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return errorResponse('invalid_request', 400);
  }
  const body = (payload ?? {}) as PostBody;
  const action = typeof body.action === 'string' ? body.action : '';

  try {
    if (action === 'unblock') {
      if (!isBlockKind(body.kind)) return errorResponse('invalid_request', 400);
      const targetId = Number(body.targetId);
      if (!Number.isSafeInteger(targetId) || targetId <= 0) return errorResponse('invalid_request', 400);
      const removed = await removeBlock(body.kind, targetId);
      return json({ ok: true, removed });
    }

    if (action === 'block' || action === 'resolve') {
      let kind: 'story' | 'comment';
      let targetId: number;
      let reportId: number | undefined;
      let reason = typeof body.reason === 'string' ? body.reason : '';

      if (action === 'resolve') {
        reportId = Number(body.reportId);
        if (!Number.isSafeInteger(reportId) || reportId <= 0) return errorResponse('invalid_request', 400);
        const report = await getReport(reportId);
        if (!report) return errorResponse('not_found', 404);
        const decision = typeof body.decision === 'string' ? body.decision : '';
        if (decision === 'dismiss') {
          const reviewed = await markReportReviewed(reportId);
          return json({ ok: true, reviewed });
        }
        if (decision !== 'block') return errorResponse('invalid_request', 400);
        // 举报一般指向评论；commentId 缺失/为 0 时退化为整篇 story
        kind = report.commentId > 0 ? 'comment' : 'story';
        targetId = report.commentId > 0 ? report.commentId : report.storyId;
        if (!reason) reason = report.reason;
      } else {
        if (!isBlockKind(body.kind)) return errorResponse('invalid_request', 400);
        kind = body.kind;
        targetId = Number(body.targetId);
        if (!Number.isSafeInteger(targetId) || targetId <= 0) return errorResponse('invalid_request', 400);
        const rawReportId = Number(body.reportId);
        if (Number.isSafeInteger(rawReportId) && rawReportId > 0) reportId = rawReportId;
      }

      const record = await addBlock({
        kind,
        targetId,
        reason,
        source: action === 'resolve' ? 'report' : (typeof body.source === 'string' ? body.source : 'manual'),
      });
      const sources = await sourcesOf(kind, targetId);
      const purgedTranslations = await purgeTranslationsBySource(sources);
      const purgedSummaries = kind === 'story' ? await purgeSummariesByStory(targetId) : 0;
      if (reportId !== undefined) await markReportReviewed(reportId);
      return json({ ok: true, block: record, purgedTranslations, purgedSummaries });
    }

    return errorResponse('invalid_request', 400, { allowedActions: ['block', 'unblock', 'resolve'] });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, 503);
  }
}