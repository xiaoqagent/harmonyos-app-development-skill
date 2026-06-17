# WebSocket 推送模式

HarmonyOS APP 通过 WebSocket 长连接接收实时推送，替代 HTTP 轮询。

## 网络架构

```
WiFi: APP → ws://192.168.3.87:8866/ws/push?client_id=xxx → xiaoq-api
5G:   APP → wss://xiaoq.xiao-q.com/ws/push?client_id=xxx → tunnel → xiaoq-api(8866)
```

## 连接生命周期

```
启动APP → detectApiUrl() → 自动推导 ws:// 或 wss:// → connect()
  → on('open') → 收到 {"type":"connected"} → 启动15秒心跳
  → on('message') → 处理推送消息（通知/授权请求）
  → on('close') → 2秒后自动重连
  → on('error') → 2秒后自动重连（⚠️ 必须加，否则断线后永久停连）
  → connect()回调error → 2秒后自动重连
  → 切换WiFi → close() → 重新 connect()
  → APP退出 → aboutToDisappear → close()
```

## 推送消息类型

| type | 方向 | 用途 |
|------|------|------|
| `connected` | server→client | 握手确认 |
| `ping`/`pong` | 双向 | 心跳保活（30秒） |
| `notification` | server→client | 通知弹窗 |
| `approve_request` | server→client | 授权请求卡片 |
| `ping`/`pong` | 双向 | 心跳保活（15秒，隧道不稳定时更短） |

## 关键实现细节

- **URL推导**：`baseUrl.startsWith('https') → 'wss://'`，否则 `'ws://'`
- **断线重连**：`setTimeout` 2秒后重试，用 `reconnectTimer` 防重复
- **心跳**：15秒 `setInterval` 发 `{type:'ping'}`
- **on('error')必须调scheduleReconnect()**：否则错误后永久停连
- **清理**：`aboutToDisappear` 中必须调 `close()`，否则内存泄漏
- **ArkTS类型**：所有回调字段用 `| undefined = undefined`，不用 `| null`
- **JSON.parse**：消息从 `ws.on('message')` 以 string 形式接收，需要 `JSON.parse`
