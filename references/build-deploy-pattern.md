# 一键编译部署 (build-deploy.ps1)

WSL 下编译鸿蒙 HAP + 部署到模拟器/真机的完整流水线，封装在单个 PowerShell 脚本中。

## 为什么需要这个脚本

- 鸿蒙工具链（hvigorw, hdc）都是 Windows PE 格式，WSL 不能直接 exec
- 编译需要 3 个环境变量（DEVECO_SDK_HOME, JAVA_HOME, NODE_HOME）
- 之前每次编译要拆成 10-15 步工具调用（cp→pwsh→grep→patch→cp→pwsh→install→verify），很容易超 max_iterations

## 脚本位置

- 项目根：`D:\05_HarmonyNext\XiaoQ\build-deploy.ps1`
- WSL 仓库：`/home/xiaoq/workspace/harmony_xiaoq_fix/build-deploy.ps1`

## 从 WSL 调用

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
  -ExecutionPolicy Bypass \
  -File "D:\05_HarmonyNext\XiaoQ\build-deploy.ps1"
```

## 参数

| 参数 | 默认 | 说明 |
|------|------|------|
| `-ProjectDir` | `D:\05_HarmonyNext\XiaoQ` | 项目路径 |
| `-RepoDir` | 空 | WSL 仓库路径，设了则同步源码后再编译 |
| `-SkipSync` | false | 跳过源码同步 |
| `-DeviceId` | `127.0.0.1:5555` | hdc 目标设备 |

## 脚本流程

```
1. 同步源码（从 RepoDir 到 ProjectDir，8个关键文件）
2. 编译 HAP（assembleHap -p buildMode=debug）
3. 检查 HAP 产物（entry-default-signed.hap）
4. 安装到设备（hdc install -r）
5. 启动 APP + 验证版本号（bm dump -> versionName）
```

## 踩坑记录

- **ExecutionPolicy**: PowerShell 默认禁止运行未签名脚本。必须加 `-ExecutionPolicy Bypass`
- **路径空格**: DevEco Studio 装在 `Program Files` 下，`-Command` 内联时引号层叠极易出错。用 `-File` + `.ps1` 文件最可靠
- **rsync 路径陷阱**: 用 rsync 同步单个文件时，如果文件列表不带目录前缀（如 `AppScope/app.json5`），会被铺平到目标根目录。用 `cp` 逐个文件最安全
- **版本号验证**: `bm dump -n` 输出多个 `versionName` 字段（模块级的为空，应用级的为实际版本）。取最后一个非空值
