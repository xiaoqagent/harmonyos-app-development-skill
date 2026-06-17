# 交互式授权卡片 Debug 记录

## 架构

```
Hermes Gateway 检测到需审批的危险操作
  → 发 approval.request 事件到 gateway_watcher
    → xiaoq-api 的 WS 未直接接 gateway 的 approval 事件
      → 手动通过 xiaoq-api /api/test-approval 端点广播

APP 端流程:
WS 收到 type:"approve_request" + run_id + command + choices
  → ChatPage.handleApproveRequest() 
    → 检测 msg.run_id 存在 → 走新格式
      → showDialog=true, dialogMode='approve'
        → ApproveDialog 弹出（4按钮）
          → 用户点击 → respondApprove(choice)
            → HermesApi.approveRun(runId, choice)
              → POST /v1/runs/{runId}/approval
```

## 关键代码位置

| 组件 | 文件 | 作用 |
|------|------|------|
| 授权卡片 UI | `ChatPage.ets ApproveDialog()` | 4个操作按钮 + 命令展示 |
| 授权处理 | `ChatPage.ets handleApproveRequest()` | 新旧格式兼容 |
| Hermes API 调用 | `HermesApi.ets approveRun()` | POST 到 Hermes |
| 测试端点 | `xiaoq-api/server.py /api/test-approval` | 手动触发广播测试 |

## 踩坑记录

### 1. `bindContentCover` 不响应 `||` 表达式

详见主技能的 §bindContentCover 陷阱。

### 2. WS 广播类型必须是 `approve_request` 不是 `notification`

`/api/push` 发的 `type:"notification"` 走的是 Toast 显示（聊天列表插一条消息），不走授权卡片流程。授权卡片必须收 `type:"approve_request"` 加上 `run_id`、`command`、`choices` 字段。

### 3. Hermes Gateway → xiaoq-api 的审批转接不存在

当前（2026-06-16）Hermes Gateway 的 `approval.request` 事件通过 WebUI 的 gateway_watcher 监控，但没有转发到 xiaoq-api 的 WebSocket 广播。所以APP不会自动收到审批请求，除非通过 xiaoq-api 手动广播 `/api/test-approval`。

如果需要实现在线审批，需要在 gateway_watcher 或 xiaoq-api 中加一个桥接层。

### 4. 测试方法

```bash
# 发送测试审批卡片到所有连接的 APP
curl -X POST http://127.0.0.1:8866/api/test-approval

# 确认 WS 连接正常
python3 -c "
import asyncio, json
async def t():
    import websockets
    async with websockets.connect('ws://127.0.0.1:8866/ws/push?client_id=test') as ws:
        print(await ws.recv())  # connected
        # 发 ping 心跳
        await ws.send(json.dumps({'type':'ping'}))
        pong = json.loads(await ws.recv())
        print(f'pong: {pong}')
asyncio.run(t())
"
```
