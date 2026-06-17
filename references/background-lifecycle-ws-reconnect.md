# 鸿蒙APP前台/后台生命周期 & WebSocket重连

## 适用场景

鸿蒙APP在后台时可能被系统挂起或限制网络连接（WebSocket在后台断连），需要切回前台时自动重连。

## 关键生命周期钩子

```typescript
@Entry
@Component
struct ChatPage {
  private pageVisible: boolean = true;
  private wsClient: WebSocketClient;

  /**
   * 页面完全显示时触发（从后台切回前台）
   */
  onPageShow(): void {
    this.pageVisible = true;
    if (!this.wsClient.isConnected()) {
      // 断线了，自动重连
      this.detectApiUrl().then((detectedUrl: string) => {
        this.setupWebSocket(detectedUrl);
        console.info('WS reconnected on foreground');
      });
    }
  }

  /**
   * 页面被覆盖时触发（推到后台）
   */
  onPageHide(): void {
    this.pageVisible = false;
    // 不主动断开WS——让系统决定是否保留连接
    // 如果系统杀了连接，onPageShow会触发重连
  }
}
```

## WebSocketClient重连准备

```typescript
export class WebSocketClient {
  private connected: boolean = false;

  public isConnected(): boolean {
    return this.connected;
  }

  // ⚠️ on('error') 也必须调 scheduleReconnect()！
  // 否则当网络中断或隧道超时时，error 事件触发后永久停连
  // 只靠 on('close') 回调不够——某些场景下 error 后不触发 close
  private setupHandlers(): void {
    this.ws.on('close', () => {
      this.connected = false;
      this.stopPing();
      this.scheduleReconnect();  // ✅ 已有
    });
    this.ws.on('error', () => {
      this.connected = false;
      this.stopPing();
      this.scheduleReconnect();  // ⚠️ 必须加！之前漏了导致永久断连
    });
  }
}
```

## 完整流程

```
APP启动 → aboutToAppear() → setupWebSocket() → WS连接成功
用户按Home → onPageHide() → pageVisible=false
系统挂起APP → WS可能被系统断开 → connected=false
用户切回前台 → onPageShow() → 检测connected=false → 自动重连
```

## 注意

- `onPageShow`/`onPageHide` 是页面的生命周期钩子，不是Ability的——在`@Component`层级可直接使用
- 不要在`onPageHide`中主动`close()` WS——系统可能保持连接，主动断开会导致不必要的重连开销
- 每次`onPageShow`都要检查connected状态，因为系统可能在后台任意时刻断连
- 结合WiFi检测：从家里到户外WiFi切换时，SSID变了也需要重建连接（在`detectApiUrl`中检测）
- `aboutToDisappear()`中仍需要清理WS（页面销毁时）
