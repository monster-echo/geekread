// backend/lib/report-store.ts
// 注意：Report.ts 为 BigInt。任何把 Report 行 JSON 序列化返回给客户端的代码，
// 必须先 `Number(r.ts)` 映射（JSON.stringify 遇 BigInt 会抛错）。
// 当前 saveReport 只写不读，无影响。
import { db } from './db';

export type ReportEntry = {
  storyId: number;
  commentId: number;
  reason: string;
  text: string;
  installId: string;
  ts: number;
};

// ---- 内存回退（dev/test）----
const memReports: ReportEntry[] = [];

export async function saveReport(entry: ReportEntry): Promise<void> {
  const client = await db();
  if (!client) {
    memReports.push(entry);
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
