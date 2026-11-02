// backend/lib/report-store.ts
// 注意：Report.ts 为 BigInt。任何把 Report 行 JSON 序列化返回给客户端的代码，
// 必须先 `Number(r.ts)` 映射（JSON.stringify 遇 BigInt 会抛错）。
import { db } from './db';

export type ReportEntry = {
  storyId: number;
  commentId: number;
  reason: string;
  text: string;
  installId: string;
  ts: number;
};

export type ReportRecord = ReportEntry & {
  id: number;
  /** 审核处置时间（null = 未处理） */
  reviewedAt: number | null;
};

// ---- 内存回退（dev/test）----
const memReports: ReportRecord[] = [];
let memNextId = 1;

export async function saveReport(entry: ReportEntry): Promise<void> {
  const client = await db();
  if (!client) {
    memReports.push({ ...entry, id: memNextId, reviewedAt: null });
    memNextId += 1;
    return;
  }
  await client.report.create({
    data: {
      storyId: entry.storyId,
      commentId: entry.commentId,
      reason: entry.reason,
      text: entry.text,
      installId: entry.installId,
      ts: BigInt(entry.ts),
    },
  });
}

/** 举报列表（按提交时间倒序，供审核管理接口使用）。 */
export async function listReports(limit = 100): Promise<ReportRecord[]> {
  const take = Math.min(Math.max(limit, 1), 500);
  const client = await db();
  if (!client) {
    return memReports.slice().sort((a, b) => b.ts - a.ts).slice(0, take);
  }
  const rows = await client.report.findMany({ orderBy: { ts: 'desc' }, take });
  return rows.map((row) => ({
    id: row.id,
    storyId: row.storyId,
    commentId: row.commentId,
    reason: row.reason,
    text: row.text,
    installId: row.installId,
    ts: Number(row.ts),
    reviewedAt: row.reviewedAt ? row.reviewedAt.getTime() : null,
  }));
}

export async function getReport(id: number): Promise<ReportRecord | undefined> {
  const client = await db();
  if (!client) return memReports.find((report) => report.id === id);
  const row = await client.report.findUnique({ where: { id } });
  if (!row) return undefined;
  return {
    id: row.id,
    storyId: row.storyId,
    commentId: row.commentId,
    reason: row.reason,
    text: row.text,
    installId: row.installId,
    ts: Number(row.ts),
    reviewedAt: row.reviewedAt ? row.reviewedAt.getTime() : null,
  };
}

/** 标记举报已处置（幂等）。 */
export async function markReportReviewed(id: number): Promise<boolean> {
  const client = await db();
  if (!client) {
    const report = memReports.find((item) => item.id === id);
    if (!report) return false;
    report.reviewedAt = Date.now();
    return true;
  }
  const result = await client.report.updateMany({ where: { id }, data: { reviewedAt: new Date() } });
  return result.count > 0;
}