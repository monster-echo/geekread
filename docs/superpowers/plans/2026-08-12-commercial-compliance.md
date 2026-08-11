# Plan 4：商业化（Pro 权益闭环）+ 合规

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal**：打通 Freemium Pro 闭环（MobileStarter 签 entitlement JWT → 客户端携带 → geekread 后端验签放 Pro 配额），并落地法律文档。

**Architecture**：entitlement 签发是**通用能力**（验证订阅 → 签 HMAC JWT），属 MobileStarter server；geekread 后端已验签（Plan 1 `lib/entitlement.ts`）；两端共享 `ENTITLEMENT_SIGNING_SECRET`。客户端把「session token」（给 MobileStarter）与「entitlement JWT」（给 geekread 后端）分开携带。

**范围**：
1. MobileStarter server：`POST /api/v1/me/entitlement`（签 JWT）+ `entitlement-token.ts` 签名库（generic）。
2. geekread：法律文档（privacy/terms/EULA，移植自 Hacki-OH `assets/*.md`，改应用名）。
3. RN + ArkTS：entitlement 服务（fetch+cache JWT）+ GeekReaderApiClient 的 Bearer 改用 entitlement JWT。
4. 合规：首次启动隐私同意门、品牌——壳已具 splash/onboarding/法律页，记配置项；内容举报记 v2。

---

### Task C1: MobileStarter — entitlement 签名库 + 端点

**Repo**：`/Volumes/MacMiniDisk/workspace/MobileStarter`（独立 git repo，新分支 `feat/entitlement-signing`）

**Files**:
- Create: `server/src/server/entitlement-token.ts`
- Create: `server/src/app/api/v1/me/entitlement/route.ts`
- Modify: `server/.env.example`（+ `ENTITLEMENT_SIGNING_SECRET`）

- [ ] `entitlement-token.ts`：`signEntitlementToken({ exp, appId, tier })` → `base64url(payload).base64url(hmac_sha256)`，与 geekread `lib/entitlement.ts` **格式一致**（同一密钥两侧通用）。
- [ ] `me/entitlement/route.ts`：`POST`，`requireAuth` → `isPro = user.tier_id != null && length>0`；`isPro` → 签 1h JWT 返 `{ token, expiresAt }`；否则 `{ token: null, expiresAt: null }`。
- [ ] `.env.example` 加 `ENTITLEMENT_SIGNING_SECRET=`（注释：与各 app 后端共享）。
- [ ] `tsc --noEmit` 通过；提交。

### Task C2: geekread 法律文档

**Files**：Create `geekread/docs/legal/{privacy-policy,terms-of-service,eula}.md`（移植 Hacki-OH `assets/*.md`，把 Hacki/GeekRead 应用名、邮箱、后端地址占位改对）。

- [ ] 复制三份，改应用名为「极客译读 / GeekRead」，补第三方 SDK 清单（IAP、埋点、翻译后端、MaaS）。
- [ ] 提交。

### Task C3: RN entitlement 服务 + Bearer 切换

**Files**:
- Create: `react-native/src/features/geek-reader/data/entitlement.ts`
- Modify: `react-native/src/features/geek-reader/data/GeekReaderApiClient.ts`（Bearer 改用 entitlement JWT）

- [ ] `entitlement.ts`：`getEntitlementToken(): Promise<string|null>`——内存缓存 + 到期前 60s 刷新；用 session token（readSessionToken）+ app headers 打 `${EXPO_PUBLIC_API_URL}/api/v1/me/entitlement`。
- [ ] GeekReaderApiClient：`authHeaders` 的 Bearer 改用 `await getEntitlementToken()`（而非 readSessionToken）；`x-install-id` 不变。
- [ ] 测试：entitlement.ts 注入 fetch mock，验证缓存/刷新；GeekReaderApiClient.test 调整对 Bearer 的断言。
- [ ] vitest + tsc 通过；提交。

### Task C4: ArkTS entitlement 服务 + Bearer 切换

**Files**:
- Create: `arkts/.../features/geek-reader/data/Entitlement.ets`
- Modify: `arkts/.../features/geek-reader/data/GeekReaderApiClient.ets`

- [ ] `Entitlement.ets`：`getEntitlementToken(): Promise<string>`——缓存 + 刷新；用 localStore.readToken() 打 MobileStarter baseUrl（需新增 `MOBILE_STARTER_BASE` 常量或读 ApiTransport 的 API_BASE——为解耦，本端单独 const）。
- [ ] GeekReaderApiClient：Bearer 改 `await getEntitlementToken()`。
- [ ] 静态校验；提交。

### Task C5: 合规配置项（记录）
- [ ] 首次启动同意门：壳 LaunchPages/Onboarding 已具备；接入隐私政策版本号 + 同意记录（`users.consent_version/consented_at` 已存在）。记入 spec 待办，不在本计划落地代码。
- [ ] 内容举报：v2（geekread 后端 storeContentReport 当时移除了 PG，v2 再接）。

---

## Self-Review
**Spec §11 覆盖**：entitlement JWT 桥接 → C1+C3+C4 ✓；Freemium 配额 → geekread 后端已有（20/500）✓；法律文档 → C2 ✓；首次同意门/注销/设置 → 壳已具，C5 记录 ✓。
**密钥一致性**：MobileStarter `signEntitlementToken` 与 geekread `hasProEntitlement` 必须同一 `ENTITLEMENT_SIGNING_SECRET`、同一 payload 格式——两侧代码对齐。
