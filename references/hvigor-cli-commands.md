# hvigor CLI 编译执行参考

基于 DevEco Studio 6.1.1 (hvigor 6.24.2) 实战验证。

## 环境变量

| 变量 | 指向 | 说明 |
|------|------|------|
| `DEVECO_SDK_HOME` | SDK根目录（含`default/`子目录） | 必须设，hvigor用它定位SDK组件。指向`D:\Program Files\Huawei\DevEco Studio\sdk`（不是`sdk\default`） |
| `JAVA_HOME` | DevEco Studio自带的 JBR | 必须设，`PackageHap`步骤需要。指向`D:\Program Files\Huawei\DevEco Studio\jbr` |
| `PATH` | 必须含 `%JAVA_HOME%\bin` | 让node能找到`java`命令 |

## 完整编译→部署→验证流水线（从WSL调用Windows工具链）

鸿蒙工具链全是 Windows PE 格式（hvigorw.js基于node.exe，其余restool.exe等），WSL不能直接exec。**通过PowerShell委托调用**。

### 从WSL调用：必须用完整路径

WSL 默认 PATH 不含 Windows 目录，`powershell.exe` 找不到。必须用完整路径：

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command '$env:DEVECO_SDK_HOME="D:\Program Files\Huawei\DevEco Studio\sdk"; $env:JAVA_HOME="D:\Program Files\Huawei\DevEco Studio\jbr"; $env:PATH="$env:JAVA_HOME\bin;$env:PATH"; Set-Location D:\05_HarmonyNext\WorldCup2026; & "D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleApp -p product=default -p buildMode=debug'
```

如果系统中 `powershell.exe` 已在 PATH 中（非WSL默认情况），也可以直接使用 `powershell.exe`。
```

### 关键说明

| 要素 | 说明 |
|------|------|
| 环境变量必须在**同一个PowerShell会话**内设置（`$env:`），然后通过 `&` 调用node |
| `JAVA_HOME` 必须设——包签名步骤 `PackageHap` 需 spawn java |
| `DEVECO_SDK_HOME` 指向 `sdk/` 根目录（含 `default/openharmony/`），不是 `sdk/default/` |
| `assembleApp` 是正确任务名——`assembleDebug`/`assembleRelease` 不是有效任务 |
| 不要在 `cmd.exe` 中调用——PowerShell才能正确处理带空格的Windows长路径 |

### 正确环境变量清单

```powershell
$env:DEVECO_SDK_HOME = "D:\Program Files\Huawei\DevEco Studio\sdk"
$env:JAVA_HOME = "D:\Program Files\Huawei\DevEco Studio\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
```

### 部署到设备

```powershell
# 安装HAP
powershell.exe -Command '& "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" install -r "D:\05_HarmonyNext\WorldCup2026\entry\build\default\outputs\default\entry-default-signed.hap"'

# 启动APP
powershell.exe -Command '& "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" shell "aa start -a EntryAbility -b WorldCup.xiaoq.profile"'

# 检查设备
powershell.exe -Command '& "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" list targets'
```

### 验证安装

```powershell
# 查bundle信息
powershell.exe -Command '& "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" shell "bm dump -n WorldCup.xiaoq.profile"'

# 确认进程在跑
powershell.exe -Command '& "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" shell "ps -ef | grep -i worldcup"'
```

### 可复用一键脚本

项目中已提供两个 .bat 模板（见 skill 的 `templates/`）：

| 脚本 | 用途 | 从WSL调用 |
|------|------|-----------|
| `build_app.bat` | 编译 + 签名 | `cmd.exe /c "pushd D:\ && D:\path\to\build_app.bat D:\05_HarmonyNext\YourProject debug"` |
| `deploy_app.bat` | 部署 HAP 到设备 | `cmd.exe /c "pushd D:\ && D:\path\to\deploy_app.bat D:\05_HarmonyNext\YourProject"` |

**注意**：`cmd.exe /c "pushd D:\ && ..."` 是必要的——WSL的CWD是UNC路径`\\wsl.localhost\...`，cmd.exe不支持UNC路径作为当前目录，`pushd D:\` 切换到Windows目录解决。

## 常用命令（Windows CMD直接执行）

```batch
# 编译（默认target）
hvigorw.bat --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap

# 编译 + 执行测试
hvigorw.bat --mode module -p module=entry@default -p product=default -p buildMode=debug runTest

# 清理构建缓存
hvigorw.bat clean
```

## DevEco Studio自带hvigorw

当项目根没有hvigorw包装器时，可以用IDE自带的：

```batch
"D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry@default -p product=default -p buildMode=debug runTest
```

## 常见失败原因

| 错误 | 原因 | 修复 |
|------|------|------|
| `modelVersion x.x.x != y.y.y` | hvigor-config.json5和oh-package.json5的版本不一致 | 统一为DevEco Studio版本号 |
| `Invalid value of DEVECO_SDK_HOME` | 路径格式不对或指向层级不对 | 指向 `sdk/` 根目录（含 `default/openharmony/`），不是 `sdk/default/` |
| `spawn java ENOENT` during PackageHap | Java不在PATH中 | 设 `JAVA_HOME` 为 `jbr/` 目录并加到PATH |
| `restool not found` | WSL下运行 | 必须在Windows上编译。WSL无Windows exe执行能力 |
| `runTest not found` | 缺少完整参数 | 补齐 `-p product=default` |
| 编译极慢(>4min) | 首次运行下载pnpm依赖 | pnpm install完成后后续编译会快很多 |
| `assembleDebug` 报not found | 任务名不对 | HarmonyOS hvigor用 `assembleApp`，不是Android Gradle的 `assembleDebug` |
| `Property 'scrollable' does not exist on type 'RowAttribute'` | API 24 Row不支持`.scrollable()` | 用 `Scroll { Row() { ... } }` 包裹 |
| `Invalid resource directory name 'rawfile'` | rawfile不能放在`base/rawfile` | 平移到 `resources/rawfile/`（与`base/`同级） |
| hdc install 报 `ExecuteCommand need connect-key` | 多个设备在线，hdc不知道选哪个 | 用 `-t <target>` 指定：`hdc -t 127.0.0.1:5555 install ...`（模拟器）或 `hdc -t 5JV0225B15002640 install ...`（USB真机） |
| 改版本号/配置文件后编译报 `manifest.json or module.json is lost` | 构建缓存过期 | 先 `hvigorw clean` 再重新编译 |
| `hvigorw` 报 `clean` 无此任务 | 任务名不完整 | 用 `hvigorw clean` 或 `hvigorw --stop-daemon` 后重建 |
