-- AlterTable: 举报处置状态
ALTER TABLE "Report" ADD COLUMN "reviewedAt" TIMESTAMP(3);

-- CreateTable: 违规内容黑名单
CREATE TABLE "BlockedContent" (
    "id" SERIAL NOT NULL,
    "kind" TEXT NOT NULL,
    "targetId" INTEGER NOT NULL,
    "reason" TEXT NOT NULL DEFAULT '',
    "source" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BlockedContent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "BlockedContent_kind_targetId_key" ON "BlockedContent"("kind", "targetId");

-- CreateIndex
CREATE INDEX "BlockedContent_kind_targetId_idx" ON "BlockedContent"("kind", "targetId");