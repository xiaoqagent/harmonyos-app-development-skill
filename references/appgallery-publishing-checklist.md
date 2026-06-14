# AppGallery Connect 上架发布核对清单

## 前置条件

- [ ] 华为开发者账号已实名认证（审核1-3天）
- [ ] 发布证书（`.cer`）已在AGC申请
- [ ] 发布Profile（`.p7b`）已在AGC申请（不需要绑定设备）
- [ ] `compatibleSdkVersion` ≤ API 22

## 签名文件清单

| 文件 | 用途 | 类型 |
|------|------|------|
| `xiaoq.p12` | 密钥库（私钥） | 发布和调试共用同一个 |
| `xiaoq_release.cer` | 发布证书 | AGC下载 |
| `WorldCup.release.profileRelease.p7b` | 发布Profile | AGC下载 |

## API版本映射（2026年6月）

| HarmonyOS | API Level | DevEco Studio | compatibleSdkVersion |
|-----------|-----------|---------------|---------------------|
| 5.0.0 | 12 | 5.0.0 | `"5.0.0(12)"` |
| 5.0.1 | 13 | 5.0.1 | `"5.0.1(13)"` |
| 5.0.2 | 14 | 5.0.2 | `"5.0.2(14)"` |
| 5.0.3 | 15 | 5.0.3 | `"5.0.3(15)"` |
| 5.0.4 | 16 | 5.0.4 | `"5.0.4(16)"` |
| 5.1.0 | 18 | 5.1.0 | `"5.1.0(18)"` |
| 6.0.0 | 20 | 6.0.0 | `"6.0.0(20)"` |
| **6.0.2** | **22** | 6.0.2 | **`"6.0.2(22)"`** ← AGC上限 |
| 6.1.0 | 23 | 6.1.0 | `"6.1.0(23)"` |
| 6.1.1 | 24 | 6.1.1 | `"6.1.1(24)"` |

## AGC上架自检错误码

| 错误码 | 信息 | 原因 | 修复 |
|--------|------|------|------|
| 9568332 | `install sign info inconsistent` | 签名证书与已安装版本不一致 | `hdc shell bm uninstall -n <bundleName>` 后重装 |
| 9568322 | `signature verification failed due to not trusted app source` | 试图hdc直装release包 | release包只能通过AGC分发，不能hdc直装 |
| AGC自检 | `当前仅支持API Level≤22的手机` | compatibleSdkVersion > 22 | 降到`6.0.2(22)`或更低 |

## Build APP vs Build HAP

- **Build HAP**：生成 `.hap` 文件，用于直机调试（debug签名）
- **Build APP**：生成 `.app` 文件，用于AGC上架（release签名）
- 菜单：Build → Build Hap(s)/APP(s) → Build APP(s)
- 输出路径：`entry/build/default/outputs/default/` 下的 `.app` 文件
- DevEco Studio 顶部工具栏的「Build Mode」下拉框可能不显示，用菜单直接构建

## 应用信息填写

上架时AGC要求填写：

| 项目 | 说明 |
|------|------|
| 应用名称 | 对外展示名 |
| 应用分类 | 如体育运动、工具等 |
| 应用简介 | 200字以内 |
| 应用截图 | 至少4张手机截图（1080x1920或以上） |
| 隐私政策URL | 必填，可用GitHub Pages托管 |
| 应用图标 | 108x108 或 216x216 |
| 测试账号 | 有登录功能时需提供 |

## Privacy Policy 快速方案

最简方案：GitHub Pages + Markdown 隐私政策模板
- 创建 `privacy-policy.md` → 推到GitHub → 开启Pages
- URL格式：`https://<username>.github.io/<repo>/privacy-policy`
