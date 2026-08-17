FROM docker.m.daocloud.io/library/node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci

FROM docker.m.daocloud.io/library/node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# schema 先于 next build 生成客户端类型
RUN npx prisma generate && npm run build

FROM docker.m.daocloud.io/library/node:22-alpine AS run
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev
COPY --from=build /app/.next ./.next
COPY --from=build /app/package.json ./package.json
COPY prisma ./prisma
COPY --from=build /app/node_modules/.prisma ./node_modules/.prisma
EXPOSE 8787
# 启动前执行迁移（幂等）；prisma CLI 已在 dependencies
CMD ["sh", "-c", "npx prisma migrate deploy && npm start"]
