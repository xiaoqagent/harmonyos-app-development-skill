# HarmonyOS NEXT Signing Checklist

## Prerequisites

- [ ] 华为开发者账号（已实名认证）- 审核1-3天
- [ ] DevEco Studio installed (Windows/Mac)
- [ ] DevEco Studio opened at least once to auto-download SDK

## Step 1: Generate Key Pair

In DevEco Studio: `Build → Generate Key and CSR`

```
Key Store File:  D:\05_HarmonyNext\project.p12
Password:        [SET AND REMEMBER]
Key Alias:       xiaoq
Validity:        10000 days (≈27 years)
Name/Surname:    xiaoq
Organization:    个人
Country/Region:  CN
```

Output: `.p12` file + `.csr` file

## Step 2: Register App on AppGallery Connect

1. Login: https://developer.huawei.com/consumer/cn/
2. My Projects → New Project → name: `XiaoQ`
3. Add App:
   - App name: `小Q`
   - Bundle name: `xiaoq.debug.profile` (must match what you'll use in app.json5)
   - Platform: `HarmonyOS`

## Step 3: Apply for Debug Certificate

AppGallery Connect → HarmonyOS API → Certificates → New Certificate

- Type: **调试证书 (Debug)**
- Name: `xiaoq_debug`
- Upload `.csr` file
- Download `.cer` file

Note: Each account limited to 2 debug certificates + 1 release certificate.

## Step 4: Register Device

AppGallery Connect → HarmonyOS API → Device Management → Register Device

- Name: `Mate80Pro` (or any identifiable name)
- UDID: Get via `hdc shell bm get --udid` or dial `*#*#1357946#*#*`

## Step 5: Create Profile

AppGallery Connect → HarmonyOS API → Profile → New Profile

- Type: **调试Profile (Debug)**
- Name: `xiaoq-debug-profile`
- App: Select `小Q` (created in Step 2)
- Certificate: Select `xiaoq_debug` (created in Step 3)
- Device: Select the registered device (from Step 4)
- Download `.p7b` file

## Step 6: Configure Project

In `build-profile.json5` (project root):

```json5
"signingConfigs": [{
  "name": "debug",
  "type": "HarmonyOS",
  "material": {
    "storeFile": "D:\\05_HarmonyNext\\project.p12",
    "storePassword": "",      // ← Fill in DevEco Studio UI
    "keyAlias": "xiaoq",
    "keyPassword": "",        // ← Fill in DevEco Studio UI
    "certpath": "D:\\05_HarmonyNext\\debug.cer",
    "profile": "D:\\05_HarmonyNext\\debug.p7b",
    "signAlg": "SHA256withECDSA"
  }
}]
```

In DevEco Studio: `File → Project Structure → Signing Configs` → select "debug" → fill in storePassword and keyPassword → OK.

## Step 7: Verify Bundle Name Matches

The `bundleName` in `AppScope/app.json5` MUST match the bundle name registered in AppGallery Connect (Step 2).

```
AppScope/app.json5:  "bundleName": "xiaoq.debug.profile"
```

## SDK Version Mapping

| DevEco Studio | HarmonyOS SDK | API Level | compatibleSdkVersion |
|--------------|---------------|-----------|---------------------|
| 6.1.0 | 6.1.0 | 23 | `"6.1.0(23)"` |
| **6.1.1** | **6.1.1** | **24** | **`"6.1.1(24)"`** |

## Files Storage

Keep all signing files together in a dedicated directory:

```
D:\05_HarmonyNext\
├── project.p12                  ← Key store
├── project.csr                  ← CSR (intermediate, can delete after cert issued)
├── xiaoq_debug.cer              ← Debug certificate
├── xiaoq_release.cer            ← Release certificate (for store release)
└── xiaoq-debug-profileDebug.p7b ← Profile (binds cert + bundle name + device)
```

## AppGallery上架签名清单

- [ ] 在AGC申请**发布证书**（不是调试证书）→ 上传.csr → 下载.cer
- [ ] 在AGC创建**发布Profile** → 绑定应用+发布证书（不需要绑定设备）→ 下载.p7b
- [ ] DevEco Studio: File → Project Structure → Signing Configs → 新增release方案
- [ ] 填入: .p12 + xiaoq_release.cer + 发布Profile.p7b + 密码
- [ ] Build → Build APP(s)（不是HAP）→ 输出.app文件
- [ ] 上传.app到AGC → 填应用信息 → 提交审核
- [ ] **compatibleSdkVersion ≤ API 22**（AGC自检限制，否则报9568322）

## 常见签名错误

| 错误码 | 信息 | 原因 | 修复 |
|--------|------|------|------|
| 9568322 | signature verification failed, not trusted app source | release签名的包直装到手机 | release包只能通过应用市场分发，不能hdc直装 |
| 9568332 | install sign info inconsistent | 设备上已有不同签名的app | 先`hdc shell bm uninstall -n <bundleName>`再装 |
| 00303074 | bundleName does not match | app.json5包名与Profile绑定的不一致 | 统一为AGC注册的包名 |
| 00303116 | storePassword length less than 32 | build-profile.json5密码被覆盖 | 在IDE中重新填写签名密码 |
