# HTTP SSE 流式聊天（HarmonyOS NEXT）

使用 `@ohos.net.http` 替代 WebSocket 实现流式聊天，绕过 Cloudflare Tunnel 对 WS 长连接的 20-60s 超时限制。

## 背景

- Cloudflare Tunnel 对 WebSocket 有硬超时（~20-60s），无法通过配置延长
- HTTP SSE 走 Tunnel 有 1800s 超时，稳定得多
- **v1.10.0** 将 XiaoQ APP 聊天从 WebSocket 迁移到 HTTP SSE
- WS 只保留给推送通知和授权卡片（短消息）

## 架构

```
APP                          xiaoq-api                    Hermes Gateway
│                            │                            │
├─ POST /api/chat/stream ───→ proxy to ─────────────────→ /v1/chat/completions
│   SSE response ←────────── SSE tokens ←─────────────── stream:true
│                            │                            │
└─ WebSocket /ws/push ──────→ 推送通知/授权卡片           │
     (不用于聊天)              │                            │
```

## ChatStreamer 实现模式

### 核心类

```typescript
import { http } from '@kit.NetworkKit';

export class ChatStreamer {
  private httpRequest: http.HttpRequest | null = null;

  public start(baseUrl: string, bodyStr: string, callbacks: {...}): void {
    this.httpRequest = http.createHttp();
    let buffer: string = '';

    // 逐 chunk 解析 SSE
    this.httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      // ArrayBuffer → string
      const uint8: Uint8Array = new Uint8Array(data);
      let text: string = '';
      for (let i = 0; i < uint8.length; i++) {
        text += String.fromCharCode(uint8[i]);
      }
      buffer += text;

      // 解析完整 SSE event（以 \n\n 分隔）
      while (true) {
        const idx = buffer.indexOf('\n\n');
        if (idx < 0) break;
        const event = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        // 解析 data: {...} 行
      }
    });

    // 流正常结束
    this.httpRequest.on('dataEnd', () => { ... });

    // 发起请求
    this.httpRequest.request(url, { method: 'POST', ... }, (err) => { ... });
  }

  public cancel(): void {
    this.httpRequest?.destroy();
  }
}
```

### 关键 API

| API | 用途 |
|-----|------|
| `http.createHttp()` | 创建 HTTP 请求对象 |
| `on('dataReceive', cb)` | 数据到达时回调（传入 `ArrayBuffer`） |
| `on('dataEnd', cb)` | 流结束回调 |
| `request(url, options, cb)` | 发起请求（error 回调兜底网络失败） |
| `destroy()` | 销毁请求（cancel 时调用） |

### SSE 解析要点

1. **缓冲区累加**：`on('dataReceive')` 可能在一个 chunk 中包含多个 SSE event，也可能一个 event 跨多个 chunk
2. **SSE 分隔符**：`\n\n` 分隔事件。用 `buffer.indexOf('\n\n')` 循环提取完整事件
3. **ArrayBuffer 解码**：`new Uint8Array(data)` → 循环 `String.fromCharCode(uint8[i])`（ArkTS 不支持 `String.fromCharCode.apply(null, [...])`）
4. **JSON 解析保护**：`JSON.parse` 包 try/catch，跳过脏数据
5. **流结束判断**：`dataEnd` + SSE 内的 `chat_done` event 双重保障
6. **取消安全**：`cancel()` 必须设 `this.cancelled = true` 防止 `dataEnd` 在 destroy 后继续触发回调

### SSE 自定义格式

服务端返回的 SSE 并非标准 OpenAI SSE，而是自定义类型标记：

```
data: {"type":"chat_token","content":"你好"}\n\n
data: {"type":"chat_done"}\n\n
data: {"type":"chat_error","message":"..."}\n\n
```

### 与 rcp 的对比

| 特性 | `@ohos.net.http` | `rcp` |
|------|-------------------|-------|
| **流式读取** | ✅ `on('dataReceive')` 逐 chunk | ❌ 无原生流式回调 |
| **SSE 解析** | ✅ 手动 buffer + split | ❌ 需要 `response.body.getReader()` 但可用性存疑 |
| **取消** | ✅ `destroy()` | ✅ `session.close()` |
| **类型安全** | ✅ ArkTS 原生支持 | ✅ ArkTS 原生支持 |

## 与 WebSocket 的核心区别

| 维度 | WebSocket (旧) | HTTP SSE (新) |
|------|---------------|---------------|
| 传输层 | 全双工，长连接 | 单向流，请求-响应 |
| 超时 | Cloudflare Tunnel 20-60s 硬限制 | HTTP 1800s 正常 |
| 适用场景 | 推送通知、授权卡片 | 流式 AI 聊天 |
| 断线影响 | 聊天中断 + 通知丢失 | 不受影响（不用于通知） |

## 经验教训

1. **不要用 WS 做长时间流式传输**：Cloudflare/NGINX/AWS ALB 都有 WS 超时限制
2. **HTTP SSE 是聊天场景的正确选择**：单向流、长超时、标准 HTTP 缓存友好
3. **WS 保持推送通知**：短消息、实时性要求高、断线重连时间短
4. **`@ohos.net.http` 比 `rcp` 更适合 SSE**：原生流式回调支持
