# ArkUI Refresh组件：下拉刷新模式

## 问题

积分榜、排行榜等非实时数据页面，需要用户主动触发数据更新，而不是后台自动轮询。

## 方案：ArkTS `Refresh` 组件

`Refresh` 是ArkUI原生的下拉刷新容器组件，与列表/滚动内容配合使用。

## 完整实现（StandingPage示例）

```typescript
import { TeamStanding } from '../model/DataTypes';
import { WorldCupApi } from '../service/WorldCupApi';

@Entry
@Component
struct StandingPage {
  @State standings: TeamStanding[] = [];
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;  // 必须是 @State

  async aboutToAppear(): Promise<void> {
    await this.fetchData();
  }

  private async fetchData(): Promise<void> {
    try {
      this.standings = await WorldCupApi.fetchStandings();
    } catch (e) {
      console.error('Fetch standings failed', e);
    }
    this.isLoading = false;
  }

  // 下拉刷新回调
  private async onRefresh(): Promise<void> {
    this.isRefreshing = true;
    try {
      this.standings = await WorldCupApi.fetchStandings();
    } catch (e) {
      // ignore
    }
    this.isRefreshing = false;  // 设回false，框架自动收回刷新动画
  }

  build() {
    Column() {
      // 标题栏（Refresh外面）
      Row() { ... }

      if (this.isLoading) {
        LoadingProgress().width(48).height(48)
      } else {
        // Refresh包裹内容区
        Refresh({ refreshing: $$this.isRefreshing, offset: 12, friction: 100 }) {
          Column() {
            // 表头
            Row() { ... }
            // 数据列表
            List() {
              ForEach(this.standings, (s: TeamStanding) => {
                ListItem() { /* 每行数据 */ }
              })
            }
          }
          .width('100%').layoutWeight(1)
        }
        .onRefreshing(() => {
          this.onRefresh();
        })
        .width('100%').layoutWeight(1)
      }
    }
    .width('100%').height('100%')
  }
}
```

## 关键点

### 1. `$$` 双向绑定

```typescript
Refresh({ refreshing: $$this.isRefreshing })
//                              ^^ 双向绑定，不是单向
```

- `$$` 是ArkTS的状态双向绑定语法
- 框架在用户下拉时设 `isRefreshing = true`，刷新完成后需要你手动设回 `false`
- 如果用 `this.isRefreshing`（单向），框架无法控制动画的收回

### 2. isRefreshing 必须是 @State

```typescript
@State isRefreshing: boolean = false;  // ✅ @State + 双向绑定
// private isRefreshing: boolean = false;  // ❌ 非@State，框架无法感知变化
```

### 3. Refresh 包裹位置

```
Column() {
  标题栏              ← Refresh外面，不参与下拉
  if (loading) {
    LoadingProgress   ← Refresh外面，加载态不需要下拉
  } else {
    Refresh {         ← 只包裹需要下拉刷新的内容区
      Column() {
        表头
        List { ... }
      }
    }
  }
}
```

### 4. onRefreshing 回调

```typescript
.onRefreshing(() => {
  this.onRefresh();  // 调用async方法
})
```

- `.onRefreshing()` 在用户松手后触发
- 回调内部调用async刷新方法
- `onRefresh` 方法末尾设 `this.isRefreshing = false`，框架自动收回刷新动画
- **不要在回调里直接写async**，用调用封装好的async方法

### 5. Refresh参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `refreshing` | `$$boolean` | 双向绑定的刷新状态 |
| `offset` | `number` | 下拉触发距离（vp），默认12 |
| `friction` | `number` | 下拉摩擦系数，越大越难拉，默认100 |

### 6. Refresh vs setInterval 选择

| 场景 | 推荐方式 | 原因 |
|------|---------|------|
| 实时比分/直播 | setInterval | 用户期望自动更新 |
| 积分榜/排行榜 | Refresh | 数据更新不频繁，按需刷新 |
| 列表/搜索结果 | Refresh | 用户触发，避免无效API调用 |
| 股票行情 | setInterval | 实时性要求高 |

### 7. 常见错误

```typescript
// ❌ 缺少 $$ → 框架无法控制刷新动画
Refresh({ refreshing: this.isRefreshing })

// ❌ isRefreshing不是@State → UI不更新
private isRefreshing: boolean = false;

// ❌ onRefresh里没设isRefreshing=false → 刷新动画永远转
private async onRefresh(): Promise<void> {
  this.isRefreshing = true;
  this.data = await fetchData();
  // 忘了 this.isRefreshing = false;
}
```
