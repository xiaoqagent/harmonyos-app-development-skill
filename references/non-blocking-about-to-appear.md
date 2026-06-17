# Non-blocking aboutToAppear 模式

当页面初始化涉及多步异步操作（读本地Preferences → 调API → 重计算）时，用非阻塞模式让页面毫秒级显示。

## 问题

预测页面 `PredictionPage.ets` 打开要等13秒才显示数据，因为 `aboutToAppear` 里串行等了3步：

```ets
async aboutToAppear(): Promise<void> {
  // ① await UserStore.getCurrentUser(getContext(this));    ~50ms
  // ② await UserStore.getNickname(...);                     ~50ms  
  // ③ this.allMatches = WorldCupApi.getMatches();           0ms (sync)
  // ④ this.isLoading = false;                               0ms
  // ⑤ await WorldCupApi.refreshScores(this.allMatches);     ~3s (API)
  // ⑥ await this.loadUserData();                            ~200ms
  // ⑦ await this.autoCalculateScores();                     ~5-10s (重计算)
  // 总计: ~13秒白屏！
}
```

## 修复

两个关键改动：

### 1. `async aboutToAppear()` → `aboutToAppear(): void`

去掉 `async`，不让生命周期等异步操作完成。`isLoading = false` 在同步代码中立即执行。

### 2. 多步异步用 `.then()` 链串联

```ets
aboutToAppear(): void {
  const ctx = getContext(this);

  // Step 1: 本地数据（不阻塞UI）
  UserStore.getCurrentUser(ctx).then(async (phone: string) => {
    if (phone.length > 0) {
      this.currentUser = phone;
      this.isRegistered = true;
      const nickname: string = await UserStore.getNickname(ctx, phone);
      if (nickname.length > 0) this.currentNickname = nickname;
      await this.loadUserData();  // 本地Preferences
    }
  }).catch((_e: Error) => { /* 用户未注册 */ });

  // Step 2: 同步骨架（0ms）
  this.allMatches = WorldCupApi.getMatches();
  this.isLoading = false;  // ← 页面立即显示

  // Step 3: 后台API+计分（页面显示后才执行）
  WorldCupApi.refreshScores(this.allMatches).then(async () => {
    if (this.isRegistered) {
      await this.autoCalculateScores();  // 用户无感
    }
  }).catch((_e: Error) => { /* API失败，用缓存 */ });
}
```

## 陷阱

- `.catch((_e)` 必须写成 `.catch((_e: Error)` —— ArkTS `arkts-no-any-unknown` 规则
- `aboutToAppear(): void` 不是 `async`，所以 `.then()` 回调必须自行处理异常
- 如果用了 `@State` 变量在 `.then()` 回调中赋值，记得回调参数类型要写对
