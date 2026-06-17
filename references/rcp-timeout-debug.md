# rcp Session 超时问题排查

## 问题现象

APP 发消息等待后报错「出错了：timeout was reached」。

## 触发条件

- APP 在 5G 公网下（不走局域网直连）
- 消息经过 Cloudflare Tunnel → xiaoq-api(8866) 反向代理 → Hermes Gateway(8642) → AI 模型
- 多跳路径增加了延迟（每跳 ~1-2s）
- AI 模型推理本身就需要 10-30 秒

## 根因

rcp SessionConfiguration **没有设置 timeout**，鸿蒙默认超时很短（约 10-15 秒），不足以等待模型响应。

## 修复

```typescript
const config: rcp.SessionConfiguration = {
  baseAddress: this.baseUrl.replace(/\/+$/, ''),
  timeout: 120000  // 2分钟，给模型推理留够时间
};
this.session = rcp.createSession(config);
```

## 对比：WiFi 路径为何没有超时

WiFi 下请求直连 Hermes Gateway，少了两跳（Tunnel + 代理），延迟低（<10ms），所以即使没设超时也不容易触发。

## 完整网络路径（5G）

```
优化前（v1.0.0 ~ v1.4.0）：
手机 → Cloudflare Tunnel → xiaoq-api(:8866) → HTTPX代理 → Hermes Gateway(:8642) → AI模型
                    ^                           ^
            ~2-3s 延迟                本地转发，~0ms

优化后（v1.5.0+，Cloudflare Tunnel 路径路由）：
手机 → Cloudflare Tunnel → Hermes Gateway(:8642) 直接 → AI模型
                     ^
            ~2-3s 延迟，少1跳
```

**路径路由优化**（2026-06-15 实施）：`xiaoq.xiao-q.com/v1/*` 通过 Cloudflare Tunnel 的 `path:` 配置直达 Hermes Gateway，跳过 xiaoq-api 反向代理层，每轮对话省 2-3 秒。APP 端代码无需改动（URL 不变）。

```yaml
# ~/.cloudflared/config.yml
  - hostname: xiaoq.xiao-q.com
    path: /v1/*
    service: http://localhost:8642
    originRequest:
      noTLSVerify: true
  - hostname: xiaoq.xiao-q.com
    service: http://localhost:8866
```

**验证**：`/v1/models` 返回401（到了Hermes Gateway）= ✅；`/health` 返回200（xiaoq-api）= ✅

## 验证

修复后在 5G 下发消息能正常等到模型回复，不会再出现 timeout 错误。
