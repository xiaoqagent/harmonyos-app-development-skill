# rcp 网络请求 API 用法与踩坑记录

> HarmonyOS `@kit.RemoteCommunicationKit.rcp` 是官方推荐替代 `@kit.NetworkKit.http` 的网络请求方案。支持Session连接池复用、拦截器、自动重定向等高级特性。

## 核心API

### 导入

```typescript
import { rcp } from '@kit.RemoteCommunicationKit';
```

### 创建Session

```typescript
const config: rcp.SessionConfiguration = {
  baseAddress: 'https://api.example.com',    // 基址，后续请求用相对路径
  headers: { 'Authorization': 'Bearer xxx' }, // 全局请求头
  requestConfiguration: {
    transfer: {
      autoRedirect: true,
      timeout: {
        connectMs: 30000,
        transferMs: 60000,
      }
    }
  }
};
const session: rcp.Session = rcp.createSession(config);
```

### 发起请求

**方式一：rcp.Request（推荐，支持自定义headers）**

```typescript
const headers: Record<string, string> = {
  'Content-Type': 'application/json',
  'Authorization': 'Bearer ' + apiKey,
  'X-Custom-Header': 'value'
};
const body: Record<string, Object> = { 'key': 'value' };
const request: rcp.Request = new rcp.Request('/api/endpoint', 'POST', headers, body);
const response: rcp.Response = await session.fetch(request);
```

❗ **rcp.Request 构造器有4个参数**：`(url: string, method: string, headers: Record<string, string>, body: Object)`。不要写成2个参数的对象形式。

**方式二：session.post() 快捷方法**

```typescript
const response: rcp.Response = await session.post('/api/endpoint', bodyObj);
```

> 快捷方法不支持自定义请求头，需要全局headers勾子或拦截器。

### 读取响应

```typescript
const statusCode: number = response.statusCode;       // 注意是 statusCode，不是 responseCode！
const result: Record<string, Object> = response.toJSON() as Record<string, Object>;
const text: string = response.toString() ?? '';       // 返回 string | null！
const headers: Record<string, string> = response.headers;
```

## 关键踩坑

### 1. `statusCode` 不是 `responseCode`

rcp.Response 用 `statusCode` 属性，不是 http 模块的 `responseCode`：

```typescript
// ❌ 错
if (response.responseCode === 200)

// ✅ 对
if (response.statusCode === 200)
```

### 2. `toString()` 返回 `string | null`

```typescript
// ❌ 会编译报错 Type 'null' is not assignable to type 'string'
const text: string = response.toString();

// ✅ 必须加兜底
const text: string = response.toString() ?? '';
```

### 3. Session必须复用

每次请求都创建新Session会：
- 失去连接池收益（每次重新TLS握手）
- 可能触发hvigor的Session数限制（第16个后失败）

**正确做法**：Session作为类成员保存，整个APP生命周期内复用。

### 4. updateConfig时重建Session

当API地址或密钥变化时：

```typescript
public updateConfig(baseUrl: string, apiKey: string): void {
  this.baseUrl = baseUrl;
  this.apiKey = apiKey;
  this.closeSession();   // 先关旧的
  this.createSession();  // 再建新的
}
```

### 5. module.json5权限

使用rcp只需要 `ohos.permission.INTERNET` 权限，与http模块相同。
