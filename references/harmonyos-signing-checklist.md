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
├── xiaoq_release.cer            ← Release certificate (for eventual store release)
└── xiaoq-debug-profileDebug.p7b ← Profile (binds cert + bundle name + device)
```
