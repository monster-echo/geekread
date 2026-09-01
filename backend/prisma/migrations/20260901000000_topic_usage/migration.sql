-- CreateTable
CREATE TABLE "TopicUsage" (
    "day" TEXT NOT NULL,
    "clientId" TEXT NOT NULL,
    "storyId" INTEGER NOT NULL,
    "requests" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "TopicUsage_pkey" PRIMARY KEY ("day","clientId","storyId")
);