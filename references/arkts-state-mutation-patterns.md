# ArkTS @State 数组内对象属性修改后必须重新赋值数组引用

`@State matches: MatchInfo[]` 上调用函数内部修改 `matches[i].homeScore = hs`，**@State 不会检测数组中已有对象的属性变更**，UI 不会重新渲染。

## 修复模式

```typescript
// ❌ 不生效
refreshScores(this.matches);  // 内部修改 m.homeScore = hs

// ✅ 必须重新赋值数组引用
refreshScores(this.matches);
this.matches = [...this.matches];  // 新数组引用 → @State 触发 re-render
```

## 适用场景

- setInterval/setTimeout 回调中 refreshScores 后
- async/.then() 回调中数据刷新后
- 任何就地修改 @State 数组元素属性后

## 标准模板

```typescript
// 自动刷新
private startAutoRefresh(): void {
  this.refreshTimerId = setInterval(() => {
    if (!this.isRefreshing) {
      this.isRefreshing = true;
      WorldCupApi.refreshScores(this.matches).then(() => {
        this.isRefreshing = false;
        this.matches = [...this.matches];  // 关键！
      });
    }
  }, 3000);
}

// aboutToAppear
aboutToAppear(): void {
  this.matches = getMatchesSync();
  this.isLoading = false;
  refreshScores(this.matches).then(() => {
    this.matches = [...this.matches];  // 关键！
  });
}
```
