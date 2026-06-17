# 部署后自测清单

每次编译部署到模拟器/真机后，按以下顺序验证功能完整性。

## 必测项（验证 CI 是否通过）

| # | 测试项 | 方法 | 预期 |
|---|--------|------|------|
| 1 | 版本号 | `hdc shell "bm dump -n xiaoq.debug.profile" \| grep versionName` | 显示最新版本号（如 1.9.0） |
| 2 | APP 进程 | `hdc shell "ps -ef \| grep xiaoq"` | 进程在运行 |
| 3 | APP 启动 | `hdc shell "aa start -a EntryAbility -b xiaoq.debug.profile"` | `start ability successfully` |

## 功能测项（需要用户配合）

| # | 测试项 | 方法 | 预期 |
|---|--------|------|------|
| 4 | 「思考中。。」泄漏 | 发一条消息，等流式回复完成 | 最终消息中没有「思考中。。」字样 |
| 5 | 历史消息 | 发几条消息 → 杀掉 APP → 重新打开 | 历史消息还原 |
| 6 | 推送通知 | 服务端发推送 `curl -X POST /api/push -d '{"title":"T","body":"B"}'` | APP 收到通知显示在聊天列表 |
| 7 | 授权卡片 | 让 Hermes 执行需要授权的操作 | 弹出4按钮卡片（仅本次/会话/始终/拒绝） |
| 8 | 后台重连 | 切到后台 → 等30秒 → 切回前台 | WebSocket 自动重连，消息正常收发 |
