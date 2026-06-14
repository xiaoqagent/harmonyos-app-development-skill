# 自动刷新模式：setInterval + isRefreshing锁

## 问题

APP打开后比赛比分不会自动更新。需要定时从API刷新比分，直到所有比赛结束。

## 错误方案

```typescript
// 500ms间隔，无锁 → API被并发请求压垮
setInterval(() => {
  WorldCupApi.refreshScores(this.matches); // 每500ms一个新请求
}, 500);
// 6个请求同时飞 → API响应变慢 → 20-30秒才全部返回
```

## 正确方案

```typescript
// SchedulePage.ets / MainPage.ets
private refreshCount: number = 0;
private refreshTimerId: number = -1;
private isRefreshing: boolean = false;

// 在 aboutToAppear 中，首次刷新后启动
async aboutToAppear(): Promise<void> {
  this.matches = WorldCupApi.getMatches(); // 同步秒加载
  this.isLoading = false;
  await WorldCupApi.refreshScores(this.matches); // 首次刷新
  this.startAutoRefresh(); // 启动定时刷新
}

private startAutoRefresh(): void {
  this.refreshCount = 0;
  this.refreshTimerId = setInterval(() => {
    this.refreshCount++;
    if (!this.isRefreshing) {
      this.isRefreshing = true;
      WorldCupApi.refreshScores(this.matches).then(() => {
        this.isRefreshing = false;
      }).catch(() => {
        this.isRefreshing = false;
      });
    }
    if (this.refreshCount >= 7 || !this.hasLiveMatch()) {
      this.stopAutoRefresh();
    }
  }, 3000);
}

private stopAutoRefresh(): void {
  if (this.refreshTimerId >= 0) {
    clearInterval(this.refreshTimerId);
    this.refreshTimerId = -1;
  }
}

private hasLiveMatch(): boolean {
  for (let i = 0; i < this.matches.length; i++) {
    if (this.matches[i].status === 'live') return true;
  }
  return false;
}

aboutToDisappear(): void {
  this.stopAutoRefresh();
}
```

## 关键设计决策

1. **3秒间隔而非500ms**：API响应本身要2-5秒，500ms间隔只会堆积请求
2. **isRefreshing锁**：保证同时只有1个请求在飞，上一次没回来就跳过本次tick
3. **then/catch都释放锁**：异常时也要 `isRefreshing = false`，否则锁死
4. **双重停止条件**：超时(7次×3s≈21s) 或 无live比赛
5. **aboutToDisappear清除定时器**：防内存泄漏
6. **setInterval回调不能async**：用 `.then()/.catch()` 链式调用

## 效果对比

| 方案 | 并发请求数 | 首次结果显示 | 总耗时 |
|------|-----------|-------------|--------|
| 500ms无锁 | 6-10个 | 等所有排队完 | 20-30秒 |
| 3s+isRefreshing锁 | 1个 | 首次返回即显示 | 2-3秒/次 |

## 适用场景

- 实时比分/状态更新
- 股票行情轮询
- 聊天消息轮询
- 任何需要定时从API拉取最新数据的场景
