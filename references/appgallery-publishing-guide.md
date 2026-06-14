# AppGallery 发布上架指南

## 前置条件

- 华为开发者账号已实名认证（审核1-3天）
- AGC上已创建应用（包名已注册）
- 有一套 `.p12` 密钥库文件

## Release 签名文件申请

### 1. 申请发布证书

AGC → HarmonyOS API → 证书 → 新增证书

- 类型：**发布证书**（不是调试证书）
- 名称：如 `xiaoq_release`
- 上传 `.csr` 文件（与debug共用同一个p12生成的csr）
- 下载 `.cer` 文件

> 每个账号限 1 个发布证书 + 2 个调试证书

### 2. 创建发布Profile

AGC → HarmonyOS API → Profile → 新增Profile

- 类型：**发布Profile**（不是调试Profile）
- 名称：如 `WorldCup.release.profile`
- 选择应用 + 发布证书
- **不需要绑定设备**（调试Profile才需要绑定设备UDID）
- 下载 `.p7b` 文件

### 3. DevEco Studio 配置 release 签名

File → Project Structure → Signing Configs → 新增签名方案：

- Name: `release`
- Store File: 同一个 `.p12`
- Certificate: 发布证书 `.cer`
- Profile: 发布Profile `.p7b`
- Store Password / Key Password: 同debug

> ⚠️ 不要覆盖已有的 debug 签名方案。两个方案并存。

## Build APP

### 菜单构建（推荐）

```
Build → Build Hap(s)/APP(s) → Build APP(s)
```

签名方案由 `build-profile.json5` 中 `products[].signingConfig` 决定。如果该字段指向 `release` 签名方案，输出的就是 release 签名的 `.app` 包。

输出路径：`entry/build/outputs/default/` 下

### 命令行构建（可选，需要 hvigorw.bat）

```powershell
cd D:\path\to\project
.\hvigorw.bat assembleApp --mode module -p product=default -p buildMode=release
```

> ⚠️ 手动创建的项目可能没有 `hvigorw.bat`。没有时用菜单构建。

### Build Mode 下拉框

DevEco Studio 顶部工具栏可能有 Build Mode 下拉框（debug/release），但不同版本/布局不一定可见。**不需要依赖它**——签名方案由配置文件决定。

## 上传 AGC

1. 登录 AppGallery Connect
2. 我的项目 → 应用 → 版本管理 → 版本信息 → 新建版本
3. 上传 `.app` 文件
4. 填写应用信息：
   - 应用名称、分类（如体育运动）
   - 应用简介（≥100字）
   - 截图（≥4张，手机尺寸）
   - 隐私政策URL（可用 GitHub Pages 免费托管）
   - 测试账号（如有登录功能）
5. 提交审核（1-3个工作日）

## Debug vs Release 签名对比

| 维度 | Debug 签名 | Release 签名 |
|------|-----------|-------------|
| 证书类型 | 调试证书 | 发布证书 |
| Profile类型 | 调试Profile（绑定设备） | 发布Profile（不绑设备） |
| 安装方式 | hdc直装 ✅ | hdc直装 ❌（报9568322），只能通过AppGallery |
| 用途 | 开发调试 | 上架发布 |
| 设备限制 | 只能装在已注册的UDID上 | 任何设备通过应用市场安装 |

## 常见错误

| 错误码 | 信息 | 原因 | 修复 |
|--------|------|------|------|
| 9568332 | install sign info inconsistent | 换了签名证书，设备上已有旧签名的app | `hdc shell bm uninstall -n <bundleName>` 卸载旧版再装 |
| 9568322 | signature verification failed due to not trusted app source | 试图用hdc直装release包 | release包不能直装，必须通过AppGallery分发 |
| 9568322 | (同上) | release证书未被设备信任 | 这是正常的，开发阶段用debug签名 |
