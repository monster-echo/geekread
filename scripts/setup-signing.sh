#!/usr/bin/env bash
# 从 .local/signing 配置 ArkTS 签名（临时，不提交）。
# 用法：
#   ./scripts/setup-signing.sh            # 用 .local/signing 里现有材料
#   ./scripts/setup-signing.sh --release  # 用 release 材料（.p12/.cer/.p7b）
#
# 材料约定（放 .local/signing/）：
#   cert.p12   密钥库
#   cert.cer   证书
#   cert.p7b   profile
#   keyAlias / keyPassword / storePassword 从 .local/env/signing.env 读
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_DIR="$ROOT/.local/signing"
PROFILE="$ROOT/arkts/build-profile.json5"

if [ ! -d "$SIGNING_DIR" ]; then
  echo "错误：.local/signing 不存在。先放入签名材料。" >&2
  exit 1
fi

# 读取密钥参数（可选）
KEY_ALIAS="${KEY_ALIAS:-debugKey}"
KEY_PASS="${KEY_PASS:-}"
STORE_PASS="${STORE_PASS:-}"
if [ -f "$ROOT/.local/env/signing.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/.local/env/signing.env"
fi

CERT="$SIGNING_DIR/cert.p12"
CER="$SIGNING_DIR/cert.cer"
P7B="$SIGNING_DIR/cert.p7b"

# 兼容：没有 cert.* 就用 default_arkts 调试材料
if [ ! -f "$CERT" ]; then
  CERT=$(ls "$SIGNING_DIR"/*.p12 2>/dev/null | head -1 || true)
  CER=$(ls "$SIGNING_DIR"/*.cer 2>/dev/null | head -1 || true)
  P7B=$(ls "$SIGNING_DIR"/*.p7b 2>/dev/null | head -1 || true)
fi
if [ -z "$CERT" ]; then
  echo "错误：.local/signing 无签名材料。" >&2
  exit 1
fi

# 备份原始 build-profile
cp "$PROFILE" "$PROFILE.bak"

# 注入签名段（用 python 更稳，处理 json5 注释）
python3 - "$PROFILE" "$CERT" "$CER" "$P7B" "$KEY_ALIAS" "$KEY_PASS" "$STORE_PASS" << 'PYEOF'
import json, sys, re

profile_path, cert, cer, p7b, alias, key_pass, store_pass = sys.argv[1:8]

with open(profile_path, 'r', encoding='utf-8') as f:
    text = f.read()

# 去掉注释（json5 的 // 注释）
text = re.sub(r'//[^\n]*', '', text)

data = json.loads(text)

signing = {
    "signingConfigs": [{
        "name": "default",
        "type": "HarmonyOS",
        "material": {
            "certpath": cer,
            "keyAlias": alias,
            "keyPassword": key_pass,
            "profile": p7b,
            "signAlg": "SHA256withECDSA",
            "storeFile": cert,
            "storePassword": store_pass,
        }
    }]
}
if "products" in data.get("app", {}):
    for p in data["app"]["products"]:
        p["signingConfig"] = "default"

data.setdefault("app", {})["signingConfigs"] = signing["signingConfigs"]

with open(profile_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f"已注入签名：{cert}")
print(f"  alias={alias} | 证书={cer} | profile={p7b}")
PYEOF

echo ""
echo "提示：签名完成构建后，用以下命令还原（避免提交密钥）："
echo "  mv $PROFILE.bak $PROFILE"
