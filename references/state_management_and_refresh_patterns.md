# HarmonyOS NEXT 状态管理与下拉刷新架构实践

本参考沉淀了在开发高频刷新、多页面联动数据流的应用（如体育赛事预测、实时比分应用）时，关于 **AppStorage 状态同步**、**Refresh 下拉刷新组件防漏** 以及 **本地 Preferences 离线缓存保底** 的最佳实践与踩坑规避。

---

## 🎯 最佳实践一：利用原生 `AppStorage` 构建全局单数据源 (SSOT)

在多页面架构中（例如：赛程页刷新了比分，预测页需要重新计算积分，积分榜页需要重载），避免使用手写的 EventBus 或 Callback 监听模式，它们在 ArkUI 中极易因页面销毁未解绑而导致**内存泄漏**。

### 1. 声明与状态注入 (Repository 层)
在管理数据的 Service 或 Repository 中，统一使用 `AppStorage` 进行全局写入。更新数据时，使用新数组/新对象直接赋值以触发响应：

```typescript
import { MatchInfo } from '../model/DataTypes';

export class DataRepository {
  // 统一数据入口：刷新所有数据并同步到 AppStorage
  static async refreshAll(context: object): Promise<void> {
    // 1. 获取最新赛程与比分
    const matches: MatchInfo[] = await WorldCupApi.refreshScores();
    
    // 2. 触发相关业务引擎结算（如预测积分自动全量结算）
    await PredictionEngine.settleAll(context, matches);
    
    // 3. 将最新状态推送到 AppStorage
    AppStorage.setOrCreate('allMatches', [...matches]);
    
    // 4. 读取最新排行榜并更新
    const leaderboard = await UserStore.getUserList(context);
    AppStorage.setOrCreate('leaderboard', [...leaderboard]);
  }
}
```

### 2. 页面端声明双向绑定
在需要消费数据的各个页面中，使用 `@StorageLink` 装饰器替换传统的 `@State`。这能实现：只要 Repository 层更新 AppStorage，所有打开的页面自动、瞬间重绘 UI。

```typescript
@Entry
@Component
struct PredictionPage {
  // 自动绑定 AppStorage 中的全局状态，无需手动在 aboutToAppear 中拉取或订阅
  @StorageLink('allMatches') allMatches: MatchInfo[] = [];
  @StorageLink('leaderboard') leaderboard: UserInfo[] = [];
  
  async aboutToAppear() {
    // 仅做初始化或用户登录状态载入
  }
}
```

---

## ⚡️ 最佳实践二：下拉刷新组件 `Refresh` 使用规避 checklist

在 ArkUI 中，`onPullRefresh` 方法写了但下拉没反应，通常是因为**漏掉了 `Refresh` 容器组件包裹**。

### 1. 结构规范
所有支持下拉刷新的列表或滚动视图，其最外层必须被 `Refresh` 组件包裹，且其绑定状态 `refreshing` 必须是双向绑定的 `@State` 或 `@StorageLink`。

```typescript
@State isRefreshing: boolean = false;

build() {
  Column() {
    // 头部导航等不参与下拉的部分放外面
    HeaderBar()

    // 下拉刷新区域
    Refresh({ refreshing: $$this.isRefreshing }) {
      List({ space: 10 }) {
        ForEach(this.allMatches, (match: MatchInfo) => {
          ListItem() {
            MatchCard({ match: match })
          }
        })
      }
      .width('100%')
      .layoutWeight(1) // 撑满除头部外的剩余空间
    }
    .onRefreshing(async () => {
      this.isRefreshing = true;
      try {
        await DataRepository.refreshAll(getContext(this));
      } catch (e) {
        // 异常处理
      }
      this.isRefreshing = false; // 务必在异步完成后复位
    })
    .layoutWeight(1)
  }
  .width('100%')
  .height('100%')
}
```

---

## 📡 最佳实践三：离线优先 (Offline-First) 与 Preferences 缓存保底

移动端网络状况复杂，当请求复杂数据（如积分排行榜、射手榜）遇到网络断开或 API 报错时，返回空数据或报错白屏是非常差的体验。

### 1. 读写分离与本地保底机制
- **数据加载**：`aboutToAppear` 或首次载入时，首要读取本地 `Preferences` 缓存，做到秒级呈现（0延迟渲染）。
- **后台更新**：呈现缓存的同时在后台发起网络请求，网络成功后更新内存与本地持久化，并通知 UI。
- **请求失败保底**：如果网络请求返回 `null` 或报错，**绝不返回空数组**，而是继续使用并提供本地缓存的最后一份正确数据。

```typescript
export class WorldCupApi {
  // 积分榜网络获取与 Preferences 持久化保底
  static async fetchStandings(context: object): Promise<TeamStanding[]> {
    const ctx = context as common.UIAbilityContext;
    const store = await preferences.getPreferences(ctx, 'wc26_cache');
    
    // 1. 尝试拉取最新网络数据
    const data = await tryFetchJson('/get/groups');
    if (data !== null) {
      try {
        const standings = parseStandings(data);
        // 成功则更新本地 Preferences 持久化缓存
        await store.put('cached_standings', JSON.stringify(standings));
        await store.flush();
        return standings;
      } catch (e) {
        // 解析失败进入保底
      }
    }
    
    // 2. 离线/请求失败保底：从本地 Preferences 读取上一次成功的完整缓存
    const fallbackRaw = await store.get('cached_standings', '[]');
    return JSON.parse(fallbackRaw as string) as TeamStanding[];
  }
}
```

---

## 🧪 最佳实践四：ArkUI 数组属性深度变化不触发重渲染坑点

在鸿蒙 NEXT 严格模式下，`@State` 或 `@StorageLink` 装饰的数组中，**其内部对象的属性发生改变**（例如 `matches[i].homeScore = 3`），可能**无法触发 UI 局部重绘**。

### 解决方案
在属性更新完成后，对数组进行**解构赋值重新赋值**，强制触发容器对状态更新的感知：

```typescript
// 更新了 matches 数组里的某个对象属性后
this.matches[index].status = 'finished';

// 关键操作：通过解构赋值重建数组引用，触发 ArkUI 组件监听机制
this.matches = [...this.matches];
```

---

## 🛡️ 最佳实践五：并发防重入锁、批量 Preferences I/O 与定时器生命周期接管

在开发高频、多页面联动的应用时，很容易在并发请求、文件 I/O 性能和系统后台资源占用上踩坑。以下是在 WorldCup2026 项目中验证过的最高效的系统架构级方案：

### 1. 并发防重入锁 (Request Guard)
*   **痛点**：用户手速快连续下拉，或者下拉刷新刚好碰撞上后台的 60 秒自动刷新定时器。两个刷新线程同时跑，会导致：重复请求 API 浪废流量、两次同时写 preferences 发生底层写冲突（轻则数据覆盖，重则 Crash）、UI 数据来回跳动。
*   **解决方案**：在 Repository 静态类中，引入一个 `isRefreshing` 的私有布尔锁。只要有一个刷新在跑，其他重入请求一律静默拦截。

```typescript
export class DataRepository {
  private static isRefreshing: boolean = false;

  static async refreshAll(context: object): Promise<void> {
    // 防并发重入锁拦截
    if (DataRepository.isRefreshing) {
      console.log('DataRepository is already refreshing, skip.');
      return;
    }
    DataRepository.isRefreshing = true;

    try {
      const ctx = context as common.UIAbilityContext;
      // 执行 API 刷新、预测积分计算、同步到 AppStorage 
    } catch (e) {
      console.error('DataRepository refreshAll error', e);
    } finally {
      // 务必在 finally 块中释放锁，避免由于异常导致死锁
      DataRepository.isRefreshing = false;
    }
  }
}
```

### 2. 批量高性能 Preferences I/O 优化
*   **痛点**：用户量和比赛场次多时，如果采用“每算完一场比赛/每算完一个用户，就向 Preferences 中 `put` 一次数据并 `flush` 到磁盘”的写法，会导致磁盘 I/O 极其高频。在 ArkTS 单线程事件循环中，高频的文件 I/O 会严重阻塞主线程，导致 UI 卡顿和帧率下降。
*   **解决方案**：先在内存中遍历修改完所有的预测和用户积分状态，在循环内部**只 `put` 进 preferences 内存实例，但不做磁盘 `flush`**。等所有数据在内存中全量算好后，在循环最外层**只执行一次全量的 `flush()`**。

```typescript
// ❌ 错误写法：在循环内部put并逐个flush (产生极度卡顿)
for (let p = 0; p < phones.length; p++) {
  // ... 计算积分
  await predStore.put('preds_' + phone, JSON.stringify(preds));
  await predStore.flush(); // 高频写盘
}

// ✅ 正确写法：内存修改，外部单次 flush
let isAnyUserUpdated = false;
for (let p = 0; p < phones.length; p++) {
  // ... 内存中更新 preds 和累计积分 ...
  if (userUpdated) {
    await predStore.put('preds_' + phone, JSON.stringify(preds));
    await predStore.put('score_' + phone, newScore);
    isAnyUserUpdated = true;
  }
}
if (isAnyUserUpdated) {
  await predStore.flush(); // 一次性持久化到磁盘，极致性能！
}
```

### 3. 下拉刷新组件异常防卡死 (菊花复位)
*   **痛点**：网络临时变差或 API 挂掉时，`refreshAll` 内部会抛出异常。如果下拉刷新组件绑定的 `refreshing` 状态仅在 `try` 成功链的末尾才被复位为 `false`，一遇到异常，刷新动画（“菊花”）就会永远转不停，用户体验崩溃。
*   **解决方案**：将 `isRefreshing = false` 或 `isPullRefreshing = false` 强制写在 `finally` 块里，保证无论网络多么糟糕、接口报什么错，刷新状态都能被百分百安全复位。

```typescript
// 页面端下拉刷新回调
private async onPullRefresh(): Promise<void> {
  this.isPullRefreshing = true;
  try {
    // 代理调用 Repository 
    await DataRepository.refreshAll(this.ctx);
  } catch (_e) {
    // 异常容错
  } finally {
    // 强制复位，防死锁
    this.isPullRefreshing = false;
  }
}
```

### 4. 定时器生命周期接管 (Lifecycle-Aware Timer)
*   **痛点**：在页面 `aboutToAppear` 中启动 `setInterval` 定时刷新比分，如果不对其进行生命周期管理，当用户切到后台、去到二级页面、或者锁屏时，定时器依然会在后台疯狂跑网络请求并计算。这会导致多余的手机发热、电量消耗以及回前台时大量的 UI 积压重载。
*   **解决方案**：将定时器的生命周期与 `@Entry` 页面的生命周期钩子 `onPageShow`（前台页面可见）与 `onPageHide`（页面不可见/切后台）进行深度绑定，在可见时启动，在不可见时销毁。

```typescript
@Entry
@Component
struct SchedulePage {
  private refreshTimerId: number = -1;

  onPageShow(): void {
    // 页面回到前台，立即启动定时刷新
    this.startAutoRefresh();
  }

  onPageHide(): void {
    // 页面切后台，立即释放定时器
    this.stopAutoRefresh();
  }

  private startAutoRefresh(): void {
    this.stopAutoRefresh(); // 避免多重定时器叠加
    this.refreshTimerId = setInterval(() => {
      DataRepository.refreshAll(this.ctx);
    }, 15000); // 15秒一次
  }

  private stopAutoRefresh(): void {
    if (this.refreshTimerId >= 0) {
      clearInterval(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
  }

  aboutToDisappear(): void {
    // 销毁时再次兜底清理
    this.stopAutoRefresh();
  }
}
```
