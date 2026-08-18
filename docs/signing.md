# 固定签名材料（debug / release 双套）

一次性配置后指纹永不变，解决两个问题：
1. DevEco 自动签名每次重新生成证书 → AGC 登记的调试指纹失效 → 华为一键登录静默授权 1001502003
2. 发布材料私钥与 Profile 声明证书不配对 → 设备验签失败（9568448）

## 目录约定（`.local/signing/`，gitignored）

```
.local/signing/
├── debug/   geekread-debug.{p12,csr,cer,p7b}
├── release/ geekread-release.{p12,csr,cer,p7b}
└── legacy/  旧的错配材料（已废弃，仅存档）
```

- `p12`/`csr`：本机已用 hap-sign-tool 生成（密钥永久固定）
- `cer`/`p7b`：从 AGC 下载（见下）
- 密码：`.local/env/signing.env`（600 权限）

## 首次配置（AGC 控制台，约 10 分钟，只做一次）

1. **调试证书**：AGC → 证书、Profile 与 APP ID → 新增调试证书 → 上传
   `.local/signing/debug/geekread-debug.csr` → 下载 `.cer` 放入 `debug/`
2. **调试 Profile**：同页 → 新增调试 Profile → 选刚建的调试证书、包名
   `com.rwecho.geekread`、勾选设备（UDID 见下）→ 下载 `.p7b` 放入 `debug/`
3. **发布证书**：同页 → 新增发布证书 → 上传
   `.local/signing/release/geekread-release.csr` → 下载 `.cer` 放入 `release/`
4. **发布 Profile**：同页 → 新增发布 Profile → 选发布证书、包名 → 下载 `.p7b` 放入 `release/`
5. **登记指纹**：项目设置 → 常规 → 「证书指纹」→ 把两条指纹都加上：
   ```bash
   ./scripts/setup-signing.sh --fingerprints
   ```
   （华为账号登录对指纹校验：调试包查调试指纹、发布包查发布指纹，两条都登记后一键登录在两种包上都可用）

## 日常使用

```bash
# 本地调试构建（固定调试签名，直接装真机）
./scripts/setup-signing.sh --debug     # 注入签名
# ... DevEco/hvigor 构建 ...
./scripts/setup-signing.sh --restore   # 构建后还原，避免密码入库

# 发布（走 hap-sign-tool，build-profile 的 signingConfigs 必须为空）
./release.sh 1.0.6                     # 用固定发布材料签名 + 上传 AGC
```

## 登记过的设备 UDID（调试 Profile 用）

- `2NX0224510021832`（测试机）：`013F931C52111CE5E90E96827551CBF9D86621F943429BF5485ABB27C2B5C921`

获取新设备 UDID：`hdc shell bm get --udid`
