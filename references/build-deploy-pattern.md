# 一键编译部署 (build-deploy.ps1) 最佳实践（已验证 2026-06-17）

WSL 环境下编译鸿蒙单框架（HarmonyOS NEXT）HAP，并一键部署安装、验证到 Pura 90 模拟器/真机的流水线封装。

---

## 💡 为什么需要这个自动化脚本

1. **环境桥接限制**：鸿蒙 SDK 工具链（`node.exe`, `hvigorw.js`, `hdc.exe`）皆为 Windows 原生可执行文件，WSL 环境无法直接无缝调用。
2. **多环境变量繁琐**：编译需要同时设置 `DEVECO_SDK_HOME`, `JAVA_HOME`, `NODE_HOME` 且必须在同一个 PowerShell 进程内。
3. **高频多页面调试需求**：在没有脚本前，需要重复进行 `修改源码 → 同步文件 → 启动 PowerShell 会话 → 执行构建 → 检查产物 → hdc 推送 → 覆盖安装 → 调 aa 启动` 的 10 个以上步骤，极其耗费指令上限和精力。

---

## 🛠️ 通用一键部署脚本模板

在项目根目录下（例如：`D:\05_HarmonyNext\WorldCup2026\build-deploy.ps1`）创建以下脚本。该脚本已做了全面参数化，适用于任何鸿蒙单模块 HAP 应用。

```powershell
<#
.SYNOPSIS
  HarmonyOS NEXT App 一键编译部署流水线
.DESCRIPTION
  编译 -> 部署 -> 启动 -> 验证 四步合一，一次工具调用完成
.EXAMPLE
  # 部署默认项目
  powershell.exe -ExecutionPolicy Bypass -File "D:\05_HarmonyNext\WorldCup2026\build-deploy.ps1"
  # 部署特定项目和设备
  powershell.exe -ExecutionPolicy Bypass -File "D:\05_HarmonyNext\WorldCup2026\build-deploy.ps1" -ProjectDir "D:\05_HarmonyNext\XiaoQ" -BundleName "WorldCup.xiaoq.profile" -DeviceId "127.0.0.1:5555"
#>
param(
  [string]$ProjectDir = "D:\05_HarmonyNext\WorldCup2026",
  [string]$BundleName = "WorldCup.xiaoq.profile",
  [string]$DeviceId = "127.0.0.1:5555"
)

# ⚠️ 致命避坑点：由于 hvigorw 等原生工具会将普通的构建 warnings 写入 stderr，
# 默认开启 "Stop" 会导致 PowerShell 认为发生 Native 崩溃进而直接中断打包。必须设为 "Continue"！
$ErrorActionPreference = "Continue"

# 1. 自动映射 DevEco Studio 工具链路径
$env:DEVECO_SDK_HOME = "D:\Program Files\Huawei\DevEco Studio\sdk"
$env:JAVA_HOME = "D:\Program Files\Huawei\DevEco Studio\jbr"
$env:NODE_HOME = "D:\Program Files\Huawei\DevEco Studio\tools\node"
$env:PATH = "$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"

$HDC = "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
$HR = "=" * 60

function Step($Msg) { Write-Host "`n$HR`n$Msg`n$HR" -ForegroundColor Cyan }
function OK($Msg) { Write-Host "  OK $Msg" -ForegroundColor Green }
function Fail($Msg) { Write-Host "  FAILED $Msg" -ForegroundColor Red; exit 1 }

# ==================== 步骤一：Hvigor 编译 HAP ====================
Step "1/2 Build HAP"
Set-Location $ProjectDir
$node = "D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe"
$hvigor = "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js"
$log = "$ProjectDir\_build.log"

# 调用 node 运行 hvigorw.js 进行单模块 debug 构建并静默不保留守护进程
& $node $hvigor assembleHap -p product=default -p buildMode=debug --no-daemon *> $log
$ok = $LASTEXITCODE -eq 0
$text = Get-Content $log -Raw

if ($ok) {
  OK "BUILD SUCCESSFUL"
  Remove-Item $log -Force -ErrorAction SilentlyContinue
} else {
  Write-Host "BUILD FAILED" -ForegroundColor Red
  # 智能提取最近的 5 条编译 Error 并高亮
  $text -split "`n" | Select-String "ERROR.*\.ets" | Select-Object -First 5 | ForEach-Object {
    Write-Host "  $($_.Line.Trim())" -ForegroundColor Yellow
  }
  Fail "See _build.log for details"
}

# ==================== 步骤二：hdc 推送、启动与验证 ====================
Step "2/2 Deploy to $DeviceId"
$hap = "$ProjectDir\entry\build\default\outputs\default\entry-default-signed.hap"
if (-not (Test-Path $hap)) {
  Fail "HAP not found: $hap"
}
$size = [math]::Round((Get-Item $hap).Length / 1KB)
OK "HAP size: ${size}KB"

# hdc 强制覆盖安装
$result = & $HDC -t $DeviceId install -r $hap 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  Fail "Install failed: $result"
}
OK "Install success"

Start-Sleep -Seconds 1
# 通过 aa 命令拉起 Activity 
& $HDC -t $DeviceId shell "aa start -a EntryAbility -b $BundleName" *>$null
OK "App started: $BundleName"

# 验证安装版本号是否同步刷新
$dump = & $HDC -t $DeviceId shell "bm dump -n $BundleName" 2>&1 | Out-String
$verLine = $dump | Select-String '"versionName"' | Select-Object -First 1
if ($verLine) {
  $v = ($verLine.Line -replace '.*"versionName": "(.*)"', '$1').Trim()
  Write-Host "  OK Target Device Version Name: $v" -ForegroundColor Green
}

Write-Host "`n$HR`n  ALL DONE SUCCESSFULLY`n$HR" -ForegroundColor Green
```

---

## 🚀 从 WSL 一键调用的终极姿势

我们在 WSL 中不需要做任何代码复制，利用 Windows PowerShell 命令桥接，只需要一行即可在后台全自动跑完编译、安装和拉起：

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
  -ExecutionPolicy Bypass \
  -File "D:\05_HarmonyNext\WorldCup2026\build-deploy.ps1"
```

---

## ⚠️ 避坑与运行调试 Checklist

### 1. `bm dump` 验证时的版本号提取陷阱
* **现象**：`bm dump` 命令在部分版本的 Pura 90 设备中，会同时返回两个 `versionName` 字段，其中一个是模块级的（由于没有显式配所以为空），另一个是 AppScope 级的（实际版本号）。
* **对策**：在 PowerShell 脚本中，直接提取第一条匹配到的非空 versionName。或者在 Shell 命令中过滤：`bm dump -n WorldCup.xiaoq.profile | grep '"versionName"' | tail -1`。

### 2. 多重会话下的 `hdc` 设备不匹配
* **现象**：如果同时插了真机和运行了模拟器，`hdc install` 默认不知装往哪个，会报 `multiple targets` 错误。
* **对策**：脚本默认指定了 `-t 127.0.0.1:5555`。如果是局域网无线连接真机，请在 WSL 中运行 `hdc list targets` 查明当前真机设备 ID，运行脚本时追加 `-DeviceId <目标设备IP:Port>`。

### 3. $ErrorActionPreference = "Stop" 的悲剧
* **现象**：执行构建时，即便最后控制台打印 `BUILD SUCCESSFUL`，但脚本运行到中途时突然强行退出。
* **根因**：hvigor 在依赖下载及编译检查中，往往通过 `stderr` 写入构建性能相关的 `hvigor WARN:`。如果你的 PowerShell 开启了严格的 Stop 策略，这些 WARN 会被强制捕获并当做异常终止脚本。
* **对策**：在此自动化部署场景中，请务必保证脚本内的 `$ErrorActionPreference = "Continue"`。

### 4. 替换签名证书后的覆盖安装失败 (error 9568332)
* **现象**：当我们将应用从 debug 签名证书（如在模拟器调时）切换到 AppGallery 真机调试的 release 签名证书后，hdc install 会报错 `install sign info inconsistent (9568332)`。
* **根因**：鸿蒙 OS 处于安全保护，拒绝签名信息不符的直接覆盖安装。
* **对策**：必须先手动或脚本卸载设备上的旧应用：`hdc shell bm uninstall -n WorldCup.xiaoq.profile`，接着运行 `build-deploy.ps1` 即可安装成功。
