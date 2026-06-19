# HarmonyOS NEXT WebSocket 断线重连与流式消息优化模式

本参考沉淀了在开发小Q APP聊天功能时，关于 **WebSocket断线UX体验**、**sync_pending消息精确替换** 以及 **超时兜底机制** 的最佳实践与踩坑规避。

---

## 🎯 问题背景

小Q APP使用WebSocket长连接做流式聊天。当用户退后台切回前台时，APP自动重连WS并请求`sync_pending`拉取离线消息。两个关键bug被修复：

1. **#10 断线错误闪现**：WS断线时立即显示红色"网络连接中断"错误，即使`sync_pending`成功也先闪现红字
2. **#11 pop()误删消息**：用`pop()`按位置删除最后一条假设的断线消息，在用户断线后发新消息等场景下误删

---

## 📡 最佳实践一：断线消息分阶段显示（温和→兜底）

### 问题
WebSocket断线时，如果直接插入红色错误提示，即使重连恢复成功，用户也能看到错误闪现（先看到红字→再被替换或消除）。这对体验是致命打击。

### 解决方案：两阶段消息策略

```
WS断线 → ① 插入温和的"正在恢复连接..."提示（中性占位）
          ② 启动10秒超时定时器
          
重连成功 → sync_pending_response 精确查找并移除占位消息，插入正常回复
超时未恢复 → 定时器触发，将占位消息改为真正的错误提示
```

### ArkTS 实现

```typescript
// 组件私有字段
private disconnectTimeout: number | undefined = undefined;

// WebSocket onDisconnect 回调
onDisconnect: () => {
  if (this.isStreaming) {
    this.isStreaming = false;
    this.isLoading = false;

    // 阶段一：温和占位消息
    const indicatorMsg: ChatMessage = {
      role: 'assistant',
      content: '⏳ 正在恢复连接...当前网络：' + this.networkMode
    };
    this.messageList.push(indicatorMsg);
    this.scheduleSaveMessages();

    // 阶段二：10秒超时兜底
    if (this.disconnectTimeout !== undefined) {
      clearTimeout(this.disconnectTimeout);
    }
    this.disconnectTimeout = setTimeout(() => {
      for (let i = this.messageList.length - 1; i >= 0; i--) {
        if (this.messageList[i].content.startsWith('⏳ 正在恢复连接...')) {
          const errReplaced: ChatMessage = {
            role: 'assistant',
            content: '❌ 网络连接中断，回复未完成。当前网络：' + this.networkMode
          };
          this.messageList.splice(i, 1, errReplaced);
          this.messageList = [...this.messageList]; // 触发 @State 更新
          this.scheduleSaveMessages();
          break;
        }
      }
      this.disconnectTimeout = undefined;
    }, 10000);
  }
}
```

### 关键设计决策

| 维度 | 选择 | 理由 |
|------|------|------|
| 占位消息语气 | "正在恢复连接..."而非"网络中断" | 用户看到中性提示不会恐慌 |
| 超时时长 | 10秒 | 覆盖sync_pending典型延迟(1-4秒)，给足够窗口 |
| 兜底消息 | 改成真正的红色错误 | 只有恢复失败时才展示错误，避免闪现 |
| 查找方式 | `startsWith('⏳ 正在恢复连接...')` | 比位置假设可靠，容忍消息列表变化 |

---

## 🎯 最佳实践二：用内容标签做精确消息替换，禁用 pop()

### 问题
原始代码使用 `this.messageList.pop()` 按位置移除最后一条消息，假设断线消息永远是最后一条。这在以下场景会出错：

- 用户断线后继续打字发送新消息
- 系统推送通知插入消息
- 连续多次断线叠加
- 用户收到其他来源的消息

### 解决方案：标签精确查找 + splice 替换

```typescript
// ❌ 错误：按位置假设
if (lastMsg.content === '...断开...') {
  this.messageList.pop();  // 可能删错消息！
}

// ✅ 正确：按内容标签精确查找
onMessage: (msg) => {
  if (msg.type === 'sync_pending_response') {
    const content = msg.content ?? '';
    if (content.length > 0) {
      // 精确查找断线恢复占位消息
      let foundIndex = -1;
      for (let i = this.messageList.length - 1; i >= 0; i--) {
        if (this.messageList[i].content.startsWith('⏳ 正在恢复连接...')) {
          foundIndex = i;
          break;
        }
      }
      
      if (foundIndex >= 0) {
        // 用 findIndex + splice 替换，而非 pop
        this.messageList.splice(foundIndex, 1);
      }
      
      // 清除超时定时器
      if (this.disconnectTimeout !== undefined) {
        clearTimeout(this.disconnectTimeout);
        this.disconnectTimeout = undefined;
      }
      
      // 插入真正的回复内容
      const syncReply: ChatMessage = {
        role: 'assistant',
        content: content
      };
      this.messageList.push(syncReply);
      this.messageList = [...this.messageList]; // 触发渲染
      this.scheduleSaveMessages();
    }
  }
}
```

### pop() vs 标签查找对比

| 维度 | pop() | 标签查找 |
|------|-------|----------|
| 定位方式 | 数组末尾 | 遍历找标签 |
| 多消息插入后 | ❌ 误删 | ✅ 精确命中 |
| 连续断线 | ❌ 只删一条 | ✅ 每条独立匹配 |
| 空列表边界 | ❌ pop undefined | ✅ 安全跳过 |
| 时间复杂度 | O(1) | O(n) |

`O(n)` 在聊天列表（通常<200条消息）中完全可接受。

---

## 🛡️ 最佳实践三：定时器生命周期全链路接管

```typescript
aboutToDisappear(): void {
  this.hermesApi.destroy();
  this.wsClient.close();
  // 清理断线超时定时器，防止页面销毁后触发
  if (this.disconnectTimeout !== undefined) {
    clearTimeout(this.disconnectTimeout);
    this.disconnectTimeout = undefined;
  }
}
```

**踩坑**：如果不在 `aboutToDisappear` 清理定时器，用户关闭聊天页后，定时器回调仍会尝试修改已销毁组件的 `@State`，导致：
- ArkUI 运行时报错（修改已挂载组件的状态）
- 潜在的内存泄漏

---

## 🧪 测试验证清单

修复后需验证以下场景：

| 场景 | 预期行为 |
|------|----------|
| 流式回复中断线→立即恢复 | 先显示"正在恢复连接..."→sync_pending返回后替换为完整回复 |
| 流式回复中断线→10秒未恢复 | "正在恢复连接..."→改为红色错误提示 |
| 断线期间用户发新消息 | 新消息在占位消息之下，sync_pending正确替换占位消息 |
| 连续两次断线 | 每条占位消息独立超时管理 |
| 退后台→关闭聊天页 | 定时器被清理，无泄漏 |
