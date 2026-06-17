# 交互式授权卡片（4选项）

## 适用场景

Hermes Agent执行危险操作时触发授权请求`approval.request`事件，APP弹出交互式授权界面让用户选择：仅本次放行 / 会话放行 / 始终允许 / 拒绝。

## 新旧格式兼容

| 字段 | 旧格式（WebSocket回复） | 新格式（Hermes API） |
|------|------------------------|---------------------|
| 识别方式 | `msg.type === 'approve_request'` | `msg.run_id !== undefined` |
| 关键字段 | `msg.id`, `msg.title`, `msg.description` | `msg.run_id`, `msg.command`, `msg.pattern_keys` |
| 响应方式 | WebSocket发送`approve_response` | `POST /v1/runs/{run_id}/approval` |

## WebSocket消息接口扩展

```typescript
export interface WsMessage {
  type: string;
  // ... 已有字段 ...
  // 授权卡片（新格式）
  run_id?: string;        // Hermes 运行ID
  command?: string;       // 需要授权的命令
  pattern_keys?: string[]; // 匹配的模式
  choices?: string[];     // 可选操作列表（如 ["once","session","always","deny"]）
}
```

## HermesApi.approveRun

```typescript
public async approveRun(runId: string, approval: string): Promise<void> {
  const requestHeaders: Record<string, string> = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + this.apiKey
  };
  const bodyObj: Record<string, Object> = { 'approval': approval };
  const request: rcp.Request = new rcp.Request(
    '/v1/runs/' + encodeURIComponent(runId) + '/approval',
    'POST', requestHeaders, bodyObj
  );
  const response: rcp.Response = await this.session.fetch(request);
  if (response.statusCode !== 200) {
    console.error('approveRun failed: HTTP ' + response.statusCode);
  }
}
```

## 授权卡片UI（bindContentCover实现）

```typescript
// ChatPage.ets

// 状态变量（单一 @State showDialog，不能用 || 表达式）
@State showDialog: boolean = false;
@State approveRunId: string = '';
@State approveCommand: string = '';
@State approvePatterns: string[] = [];
@State approveInProgress: boolean = false;

// 消息处理器
private handleApproveRequest(msg: WsMessage): void {
  if (msg.run_id !== undefined) {
    // 新格式
    this.approveRunId = msg.run_id as string;
    this.approveCommand = msg.command as string ?? '';
    this.approvePatterns = (msg.pattern_keys as string[]) ?? [];
    this.showSettings = false;  // 关闭设置面板（如果有）
    this.showDialog = true;     // 单一变量控制显示
    this.approveInProgress = false;
  } else {
    // 旧格式回退...
  }
}

// 授权响应
private async respondApprove(choice: string): Promise<void> {
  this.approveInProgress = true;
  try {
    await this.hermesApi.approveRun(this.approveRunId, choice);
    // 显示结果到聊天框
  } catch (error) {
    // 显示错误
  } finally {
    this.showApproveDialog = false;
    this.approveInProgress = false;
  }
}

```
// ⚠️ 不能写 bindContentCover(this.showSettings || this.showApproveDialog, ...)
// ArkTS 不会追踪 || 表达式中的 @State 变化，弹窗不显示
// 必须用单一 @State 变量控制
@State showDialog: boolean = false;
...
this.showDialog = true;   // 触发弹窗
this.showDialog = false;  // 关闭弹窗

// DialogLayer：showSettings 区分显示 SettingsPanel 还是 ApproveDialog
.bindContentCover(this.showDialog, this.DialogLayer())

@Builder
DialogLayer() {
  if (this.showSettings) {
    this.SettingsPanel();
  } else {
    this.ApproveDialog();
  }
}

// 打开设置时同时设置 showSettings + showDialog
this.showSettings = true;
this.showDialog = true;

// 收到授权请求时清除 showSettings + 设置 showDialog
this.showSettings = false;
this.showDialog = true;
```
@Builder
ApproveDialog() {
  Column() {
    // 头部：🔐 + 授权请求
    // 命令代码块：黑底白字Courier
    // 匹配模式标签：Wrap布局
    // 四按钮 2行×2列：
    //   [▶️ 仅本次放行] [🔄 会话放行]
    //   [✅ 始终允许]  [⛔ 拒绝]
    // 处理中：LoadingProgress
  }
  .padding(24).borderRadius({ topLeft: 20, topRight: 20 })
}
```

## 四按钮颜色方案

| 操作 | 颜色 | emoji | 背景 |
|------|------|-------|------|
| 仅本次放行 | 深色字 | ▶️ | `#F0F5FF` (浅蓝) |
| 会话放行 | 深色字 | 🔄 | `#F0FFF0` (浅绿) |
| 始终允许 | 白字 | ✅ | `#4CAF50` (绿) |
| 拒绝 | 白字 | ⛔ | `#FF5252` (红) |
