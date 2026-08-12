# 极客译读 · ArkTS 端构建

HarmonyOS NEXT（API 18）ArkTS 原生端。命令行用 DevEco 自带的 hvigorw（仓库不带 wrapper 脚本）。

## 前置

- DevEco Studio（含 hvigorw + SDK）。本机路径示例：`/Applications/DevEco-Studio.app`
- Node 在 PATH（`NODE_HOME` 或 PATH 含 node）

## 首次：local.properties

在 `arkts/local.properties`（已 gitignore，机器相关）写 SDK 路径：

```
hwsdk.dir=/Applications/DevEco-Studio.app/Contents/sdk
```

## 命令行构建（类型检查 + 打包 unsigned HAP）

```bash
cd arkts
HVIGOR=/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw
$HVIGOR clean --no-daemon                                   # 配置加载 + 类型检查
$HVIGOR --mode module -p product=default -p driver=module assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`

> `No signingConfig found` 是预期警告（mobileui 壳不带签名配置）。上架前在 DevEco 配置签名（debug/release p12 + profile）后再 `SignHap`。

## IDE

DevEco Studio → Open → 选 `arkts/` 目录 → Sync → Run/Build。真机/模拟器渲染验证需在 DevEco 内启动设备。
