-- CreateTable
CREATE TABLE "HnItem" (
    "id" INTEGER NOT NULL,
    "type" TEXT,
    "by" TEXT,
    "time" INTEGER,
    "text" TEXT,
    "url" TEXT,
    "title" TEXT,
    "score" INTEGER,
    "descendants" INTEGER,
    "kids" INTEGER[],
    "deleted" BOOLEAN NOT NULL DEFAULT false,
    "dead" BOOLEAN NOT NULL DEFAULT false,
    "missing" BOOLEAN NOT NULL DEFAULT false,
    "raw" JSONB,
    "fetchedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "HnItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StoryList" (
    "type" TEXT NOT NULL,
    "ids" INTEGER[],
    "fetchedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StoryList_pkey" PRIMARY KEY ("type")
);

-- CreateTable
CREATE TABLE "Translation" (
    "id" SERIAL NOT NULL,
    "hash" TEXT NOT NULL,
    "lang" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "result" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Translation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Summary" (
    "id" SERIAL NOT NULL,
    "hash" TEXT NOT NULL,
    "storyId" INTEGER NOT NULL,
    "lang" TEXT NOT NULL,
    "result" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Summary_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "QuotaUsage" (
    "day" TEXT NOT NULL,
    "clientId" TEXT NOT NULL,
    "used" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "QuotaUsage_pkey" PRIMARY KEY ("day","clientId")
);

-- CreateTable
CREATE TABLE "Report" (
    "id" SERIAL NOT NULL,
    "storyId" INTEGER NOT NULL,
    "commentId" INTEGER NOT NULL,
    "reason" TEXT NOT NULL,
    "text" TEXT NOT NULL DEFAULT '',
    "installId" TEXT NOT NULL,
    "ts" BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT "Report_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "HnItem_type_fetchedAt_idx" ON "HnItem"("type", "fetchedAt");

-- CreateIndex
CREATE UNIQUE INDEX "Translation_hash_key" ON "Translation"("hash");

-- CreateIndex
CREATE INDEX "Translation_lang_idx" ON "Translation"("lang");

-- CreateIndex
CREATE UNIQUE INDEX "Summary_hash_key" ON "Summary"("hash");

-- CreateIndex
CREATE INDEX "Report_ts_idx" ON "Report"("ts");
