# WSL → PowerShell CLI 编译部署全流程（已验证 2026-06-16）

通过 PowerShell 委托从 WSL 调用 Windows 鸿蒙工具链，实现一键编译+部署。

## 三个环境变量（缺一不可）

```powershell
$env:DEVECO_SDK_HOME = "D:\Program Files\Huawei\DevEco Studio\sdk"   # 指向 sdk/ 根目录（含 default/openharmony/）
$env:JAVA_HOME = "D:\Program Files\Huawei\DevEco Studio\jbr"        # 内嵌 JBR JRE，PackageHap 签名步骤需要
$env:NODE_HOME = "D:\Program Files\Huawei\DevEco Studio\tools\node" # hvigorw 需要 node
$env:PATH = "$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"
```

**注意**：
- `DEVECO_SDK_HOME` 指向 `sdk/` 根目录，**不是** `sdk/default/openharmony/`
- `JAVA_HOME` 用 DevEco Studio 自带的 `jbr/`，不是系统 JDK。不设会报 `spawn java ENOENT`
- 三个变量必须在 **同一个 PowerShell 会话中全部设置**，不能跨 `&` 或进程。WSL 的 `export` 对 PowerShell 不可见

## 编译

```powershell
Set-Location D:\05_HarmonyNext\XiaoQ
& "D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" `
  "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" `
  assembleHap -p product=default -p buildMode=debug --no-daemon
```

**关键细节**：
- ❌ `--mode=debug` 不是有效参数（报 `Unknown mode 'debug'`）。用 `-p buildMode=debug`
- ❌ 用 `hvigorw.bat` 也可以但需要更多 PATH 配置。**用 `node.exe` 直接跑 `hvigorw.js` 最可靠**
- ✅ `assembleHap` 是编译签名单模块 HAP 的正确任务名（不是 `assembleDebug`）
- `--no-daemon` 避免后台进程残留

## 部署

```powershell
$hdc = "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc list targets                     # 查看设备
& $hdc -t <device_id> install -r "<hap_path>\entry-default-signed.hap"  # -r 覆盖安装
& $hdc -t <device_id> shell "aa start -a EntryAbility -b <bundleName>"  # 启动
& $hdc -t <device_id> shell "bm dump -n <bundleName>"                   # 验证
```

## 从 WSL 一行调用（已验证模板）

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command '
$env:DEVECO_SDK_HOME = "D:\Program Files\Huawei\DevEco Studio\sdk"
$env:JAVA_HOME = "D:\Program Files\Huawei\DevEco Studio\jbr"
$env:NODE_HOME = "D:\Program Files\Huawei\DevEco Studio\tools\node"
$env:PATH = "$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"
Set-Location D:\05_HarmonyNext\XiaoQ
Write-Host "=== Compiling ==="
& "D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleHap -p product=default -p buildMode=debug --no-daemon 2>&1
Write-Host "Build exit: $LASTEXITCODE"
'
```

## 已知问题

- **cmd.exe 不可用**：从 WSL UNC 路径（`\\wsl.localhost\...`）启动 `cmd.exe` 会报 "UNC paths are not supported"，默认到 `C:\Windows`。必须用 PowerShell
- **中文编码**：PowerShell 输出可能含 GBK 中文，捕获时注意 `encoding='utf-8', errors='replace'`
- **rsync 路径陷阱**：从 WSL rsync 文件到 Windows 时，`rsync src/file /mnt/d/Project/` 会把文件放到 `/mnt/d/Project/file` 而不是 `/mnt/d/Project/src/file`。需要 `rsync -av src/ /mnt/d/Project/src/`。或者用 `cp` 逐个文件复制到正确子目录
- **PowerShell 输出截断**：`2>&1` 后管道到 `tail` 可能丢失尾行。用 `Select-String -Pattern "BUILD|ERROR"` 过滤更可靠
