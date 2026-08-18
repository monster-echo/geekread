#!/usr/bin/env bash
# =============================================================================
# 固定签名材料注入（debug / release 双套，指纹永不变）。
#
# 用法：
#   ./scripts/setup-signing.sh --debug         # 注入固定调试签名（DevEco/hvigor 构建直接装真机）
#   ./scripts/setup-signing.sh --release       # 注入固定发布签名
#   ./scripts/setup-signing.sh --fingerprints  # 打印两套证书 SHA256 指纹（AGC 登记用）
#   ./scripts/setup-signing.sh --restore       # 还原 build-profile.json5（去掉注入）
#
# 材料约定（.local/signing/，gitignored，一次生成长期使用）：
#   debug/geekread-debug.{p12,csr,cer,p7b}     csr 由本仓库生成；cer/p7b 从 AGC 下载
#   release/geekread-release.{p12,csr,cer,p7b}
# 密码：.local/env/signing.env（DEBUG_* / RELEASE_*，600 权限）
#
# 首次配置见 docs/signing.md（AGC 上传 CSR → 下载证书/Profile → 放入对应目录）。
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_DIR="$ROOT/.local/signing"
PROFILE="$ROOT/arkts/build-profile.json5"
ENV_FILE="$ROOT/.local/env/signing.env"

MODE="${1:---debug}"

if [ ! -f "$ENV_FILE" ]; then
  echo "错误：缺少 $ENV_FILE（密码文件）。" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

case "$MODE" in
  --fingerprints)
    echo "== 证书 SHA256 指纹（登记到 AGC：项目设置 → 常规 → 证书指纹）=="
    for kind in debug release; do
      cer="$SIGNING_DIR/$kind/geekread-$kind.cer"
      if [ -f "$cer" ]; then
        fp=$(openssl x509 -inform der -in "$cer" -noout -fingerprint -sha256 2>/dev/null \
          || openssl x509 -in "$cer" -noout -fingerprint -sha256 2>/dev/null)
        plain=$(echo "${fp#sha256 Fingerprint=}" | tr -d ':' | tr 'A-F' 'a-f')
        echo "$kind: $plain"
      else
        echo "$kind: 未找到 ${cer}（先按 docs/signing.md 完成 AGC 步骤）"
      fi
    done
    exit 0
    ;;
  --restore)
    if [ -f "$PROFILE.bak" ]; then
      mv "$PROFILE.bak" "$PROFILE"
      echo "已还原 $PROFILE"
    else
      echo "无 .bak 可还原"
    fi
    exit 0
    ;;
  --debug|--release)
    KIND="${MODE#--}"
    ;;
  *)
    echo "用法：setup-signing.sh --debug | --release | --fingerprints | --restore" >&2
    exit 1
    ;;
esac

if [ "$KIND" = "debug" ]; then
  KEY_ALIAS="$DEBUG_KEY_ALIAS"; KEY_PASS="$DEBUG_KEY_PASS"; STORE_PASS="$DEBUG_STORE_PASS"
else
  KEY_ALIAS="$RELEASE_KEY_ALIAS"; KEY_PASS="$RELEASE_KEY_PASS"; STORE_PASS="$RELEASE_STORE_PASS"
fi

CERT="$SIGNING_DIR/$KIND/geekread-$KIND.p12"
CER="$SIGNING_DIR/$KIND/geekread-$KIND.cer"
P7B="$SIGNING_DIR/$KIND/geekread-$KIND.p7b"

for f in "$CERT" "$CER" "$P7B"; do
  if [ ! -f "$f" ]; then
    echo "错误：缺少 $f" >&2
    echo "p12/csr 已生成；.cer/.p7b 需按 docs/signing.md 在 AGC 申请后放入。" >&2
    exit 1
  fi
done

cp "$PROFILE" "$PROFILE.bak"

python3 - "$PROFILE" "$CERT" "$CER" "$P7B" "$KEY_ALIAS" "$KEY_PASS" "$STORE_PASS" << 'PYEOF'
import json, re, sys

profile_path, cert, cer, p7b, alias, key_pass, store_pass = sys.argv[1:8]
text = open(profile_path, encoding='utf-8').read()
text = re.sub(r'//[^\n]*', '', text)
data = json.loads(text)

data.setdefault('app', {})['signingConfigs'] = [{
    'name': 'default',
    'type': 'HarmonyOS',
    'material': {
        'certpath': cer,
        'keyAlias': alias,
        'keyPassword': key_pass,
        'profile': p7b,
        'signAlg': 'SHA256withECDSA',
        'storeFile': cert,
        'storePassword': store_pass,
    },
}]
for p in data['app'].get('products', []):
    p['signingConfig'] = 'default'

open(profile_path, 'w', encoding='utf-8').write(json.dumps(data, ensure_ascii=False, indent=2))
kind = '调试' if 'debug' in cert else '发布'
print(f'已注入固定{kind}签名：{cert}')
print(f'  alias={alias} | 证书={cer} | profile={p7b}')
PYEOF

echo ""
echo "构建完成后还原（避免提交密码）：./scripts/setup-signing.sh --restore"
