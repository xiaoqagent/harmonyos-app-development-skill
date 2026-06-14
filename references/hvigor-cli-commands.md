# hvigor CLI 编译执行参考

基于 DevEco Studio 6.1.1 (hvigor 6.24.2) 实战验证。

## 环境变量

| 变量 | 指向 | 说明 |
|------|------|------|
| `DEVECO_SDK_HOME` | SDK根目录（含`default/`子目录） | 必须设，hvigor用它定位SDK组件。指向`D:\Program Files\Huawei\DevEco Studio\sdk`（不是`sdk\default`） |
| `HOS_SDK_HOME` | 同上 | 部分版本也用这个变量 |

## 常用命令

```powershell
# 编译（默认target）
hvigorw.bat --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap

# 编译 + 执行测试
hvigorw.bat --mode module -p module=entry@default -p product=default -p buildMode=debug runTest

# 清理构建缓存
hvigorw.bat clean
```

## DevEco Studio自带hvigorw

当项目根没有hvigorw包装器时，可以用IDE自带的：

```powershell
"D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry@default -p product=default -p buildMode=debug runTest
```

## 常见失败原因

| 错误 | 原因 | 修复 |
|------|------|------|
| `modelVersion x.x.x != y.y.y` | hvigor-config.json5和oh-package.json5的版本不一致 | 统一为DevEco Studio版本号 |
| `Invalid DEVECO_SDK_HOME` | 路径格式不对 | 指向`sdk/`，不是`sdk/default/`。WSL下用`/mnt/d/...`格式，Windows用`D:/...`格式 |
| `restool not found` | WSL下运行 | 必须在Windows上编译。WSL无Windows exe执行能力 |
| `runTest not found` | 缺少完整参数 | 补齐`-p product=default` |
| 编译极慢(>4min) | 首次运行下载pnpm依赖 | pnpm install完成后后续编译会快很多。`--no-daemon`避免daemon进程残留 |
