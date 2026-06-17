# 华为 Push Kit 推送通道

## 架构概述

```
cron/agent → Hermes Gateway → xiaoq-api:/api/push
                                         ↓
                              ┌──────────────────────┐
                              │    推送调度器          │
                              ├──────────────────────┤
                              │ • SSE广播(给SSE订阅者) │
                              │ • WebSocket广播       │
                              │ • Push Kit REST API   │
                              └──────────────────────┘
                                         ↓
                              华为 Push Kit 服务器
                                         ↓
                              手机系统级通知栏弹窗
                            (APP被杀也能收到)
```

## 服务端（xiaoq-api）

### 配置

在 `~/.hermes/.env` 中添加（从 AppGallery Connect 获取）：

```
PUSH_APP_ID=你的AppID
PUSH_APP_SECRET=你的AppSecret
```

⚠️ **用 Python 写环境变量，不要用 echo**：`echo 'PUSH_APP_SECRET=540698...' >> .env` 可能截断长字符串（因 shell 转义、heredoc 边界等）。**实战踩坑**：实际写入的是 `540698...AD93`（13字符含点号），而非预期的完整 64 字符 hex 串。用 `execute_code` 或 Python 的 `open().write()` 操作。事后用 `grep PUSH_APP_SECRET ~/.hermes/.env | cut -d= -f2 | wc -c` 验证长度。

### AppGallery Connect 配置（必读）

1. 登录 AGC，创建应用，包名填 `xiaoq.debug.profile`
2. 进入 Push Kit → 开通服务
3. 以下选项**全部不需要开通**（为安卓 AOSP 设计，鸿蒙 NEXT 不兼容）：
   - 项目回执状态 ❌ | 精准推送能力 ❌ | 应用回执状态 ❌ | 其他安卓推送 ❌ | 自分类权益 ❌
4. 在「应用配置」页面下载 `agconnect-services.json`，放入 `entry/agconnect-services.json`
5. 从「应用配置」页获取 `APP ID` 和顶部的 `Client Secret`
6. **确认客户端已注册token**：检查 `~/.hermes/push_tokens.json` 是否有 `token` 字段（长度>10）。APP 启动后会自动调用 `pushService.getToken()` 并 POST 到 `/api/push/register`。如果文件为空或只有无关测试数据，说明 APP 端 Push Kit 初始化未完成
7. **验证服务端配置**：`grep PUSH_APP ~/.hermes/.env` 确认 ID 和 Secret 都存在。重启服务后 `journalctl --user -u xiaoq-api --no-pager | grep -i pushkit` 应能看到 `Register` 日志。发一条测试推送后检查日志是否有 `Sent to N devices` 或 `Auth failed`

### OAuth 凭证问题（已知踩坑）

Push Kit OAuth 需要正确的 `client_id` + `client_secret` 组合。以下凭证**已验证**：

| 尝试的 client_id | 尝试的 client_secret | 结果 |
|-----------------|---------------------|------|
| APP ID (e.g. 6917608171199263110) | 通用 Client Secret (64 hex) | ❌ error 1101 / sub_error 12304 |
| Service Account ID (e.g. 118035617) | Service Account secret (32 hex) | ❌ error 1101 / sub_error 20172 |
| APP ID + OAuth 2.0 Client Secret | `5f495c12...` | ✅ **OAuth 成功！** token 获取成功 |
| **推送阶段** | 同上 | ⚠️ Push: "All the tokens are invalid" |

**最终结论（2026-06-15 验证）**：

**OAuth 认证**使用「应用配置」页面的 OAuth 2.0 专用凭证：
- `client_id` = **APP ID**（如 `6917608171199263110`，见应用信息区）
- `client_secret` = **OAuth 2.0 Client Secret**（在应用配置页下翻「OAuth 2.0 客户端ID」区域，不是顶部的通用 Client Secret）

**推送失败（"All the tokens are invalid"）原因**：
设备注册的 push token 来自旧版 APP（编译时无 `agconnect-services.json`），华为服务器不认可。
**修复**：在项目中放入 `agconnect-services.json` → 重新编译 HAP → 装到手机 → APP 重新注册 token → 再推即可。

### 敏感文件处理

`agconnect-services.json` 和 `agc-apiclient-*.json` 包含 API 密钥，**绝对不能提交到 Git**。加入 `.gitignore`：

```gitignore
# AGC credentials
agconnect-services.json
entry/agconnect-services.json
agc-apiclient-*.json
entry/agc-apiclient-*.json
```
```

### 令牌注册端点

`POST /api/push/register`

```json
{ "token": "push_token_from_harmonyos", "device_id": "harmony-xxxxx" }
```

去重策略：同 device_id 更新 token，不同则新增。

### 推送流程

1. 获取 OAuth 2.0 Access Token（client_credentials）
2. 按 500 个 token 一批，调用华为 Push Kit REST API
3. 记录推送结果日志

```python
POST https://oauth-login.cloud.huawei.com/oauth2/v3/token
Body: grant_type=client_credentials&client_id=xxx&client_secret=xxx

POST https://push-api.cloud.huawei.com/v1/{appId}/messages:send
Authorization: Bearer {access_token}
Body: {
  "validate_only": false,
  "message": {
    "token": ["token1", "token2", ...],
    "notification": { "title": "...", "body": "..." },
    "android": {
      "notification": {
        "click_action": { "type": 1 },
        "badge": { "add_num": 1, "class": "entryability.EntryAbility" }
      }
    }
  }
}
```

### 集成到 /api/push

当推送消息到达 `/api/push` 时，自动触发三条路径：

```python
asyncio.create_task(push_events.broadcast(message))    # SSE
asyncio.create_task(manager.broadcast(notification))    # WebSocket
asyncio.create_task(_push_to_huawei(title, text, src))  # Push Kit
```

## 客户端（HarmonyOS NEXT）

### 初始化推送

```typescript
// EntryAbility.ets
import { pushService } from '@kit.PushKit';
import { rcp } from '@kit.RemoteCommunicationKit';

onCreate(): void {
  this.initPushKit();
}

private initPushKit(): void {
  pushService.getToken().then((token: string) => {
    if (token !== '') this.registerPushToken(token);
  }).catch((error: Error) => {
    console.error('getToken failed: ' + error);
  });
}

private async registerPushToken(token: string): Promise<void> {
  const session = rcp.createSession({ baseAddress: 'https://xiaoq.xiao-q.com' });
  const request = new rcp.Request(
    '/api/push/register', 'POST',
    { 'Content-Type': 'application/json' },
    { 'token': token, 'device_id': 'harmony-' + Date.now() }
  );
  const response = await session.fetch(request);
  if (response.statusCode === 200) console.info('Push token registered');
  session.close();
}
```

### PushServiceAbility（接收推送回调 + 发本地通知）

```typescript
// PushServiceAbility.ets
import { PushServiceAbility } from '@kit.PushKit';
import { notificationManager } from '@kit.NotificationKit';

export default class XiaoQPushService extends PushServiceAbility {
  onReceiveMessage(data: string): void {
    console.info('[PushService] Received: ' + data);
    try {
      const msg: Record<string, Object> = JSON.parse(data) as Record<string, Object>;
      const title: string = (msg['title'] as string) ?? '小Q';
      const body: string = (msg['body'] as string) ?? (msg['alert'] as string) ?? data;
      this.publishNotification(title, body);
    } catch (error) {
      this.publishNotification('小Q', data);
    }
  }

  private async publishNotification(title: string, body: string): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: new Date().getTime(),
      content: {
        contentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: body }
      }
    };
    await notificationManager.publish(request);
  }
}
```

### module.json5 注册 PushServiceAbility

PushServiceAbility 必须作为独立 ability 注册，否则推送消息不会路由到它：

```json5
{
  \"module\": {
    \"abilities\": [
      {
        \"name\": \"EntryAbility\",
        \"srcEntry\": \"./ets/entryability/EntryAbility.ets\",
        // ... 主 Ability 配置
      },
      {
        \"name\": \"PushServiceAbility\",
        \"srcEntry\": \"./ets/entryability/PushServiceAbility.ets\",
        \"type\": \"pushService\",
        \"exported\": true
      }
    ]
  }
}
```

### 权限

Push Kit 通过 `@kit.PushKit` SDK 自动管理权限，无需手动声明 `ohos.permission.PUSH`（该权限在 SDK 中不可直接声明）。

### 当前状态（2026-06-15）

- 服务端代码已完成：注册端点 + Push Kit REST API 推送
- 客户端代码已完成：EntryAbility 获取 token + 注册 + PushServiceAbility
- **待完成**：在 AppGallery Connect 创建应用、启用 Push Kit、下载 `agconnect-services.json`、配置 `PUSH_APP_ID` 和 `PUSH_APP_SECRET`
