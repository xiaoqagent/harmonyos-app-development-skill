# 本地数据缓存模式：preferences缓存API结果

## 核心思路

已获取的API数据（如比赛结果、积分榜）持久化到本地preferences，下次打开APP直接读缓存，只对live/未缓存的比赛调API。

## 适用场景

- API数据更新频率低（比赛结果一旦确定就不会变）
- 用户频繁打开APP（每次白等3-4秒不可接受）
- API有调用限制或响应慢

## 架构设计

```
首次打开:
  loadPersistedCache()  → 从preferences读缓存（毫秒级）
  getMatches()          → 硬编码骨架 + 缓存比分 → 瞬间显示
  refreshScores()       → API拉最新 → 更新matches + 写入缓存

第二次打开:
  loadPersistedCache()  → 已完赛的比分直接从缓存读，0网络
  getMatches()          → 上次完赛的比赛立刻显示比分
  refreshScores()       → 只有live/未缓存的比赛需要API
```

## 实现代码

### WorldCupApi层（缓存读写）

```typescript
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class WorldCupApi {
  // 内存缓存（当前会话秒级访问）
  private static scoreCache: Record<string, Record<string, string>> = {};
  private static cacheLoaded: boolean = false;

  // 从本地存储加载缓存（只需调一次）
  static async loadPersistedCache(context: object): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = context as common.UIAbilityContext;
      const store: preferences.Preferences = await preferences.getPreferences(ctx, 'wc26_cache');
      const raw: preferences.ValueType = await store.get('scores', '{}');
      WorldCupApi.scoreCache = JSON.parse(raw as string) as Record<string, Record<string, string>>;
      WorldCupApi.cacheLoaded = true;
    } catch (_e) {
      // ignore
    }
  }

  // 保存缓存到本地存储
  private static async saveToPersistence(context: object): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = context as common.UIAbilityContext;
      const store: preferences.Preferences = await preferences.getPreferences(ctx, 'wc26_cache');
      await store.put('scores', JSON.stringify(WorldCupApi.scoreCache));
      await store.flush();
    } catch (_e) {
      // ignore
    }
  }

  // 秒返赛程 + 内存缓存比分（0网络等待）
  static getMatches(): MatchInfo[] {
    const matches: MatchInfo[] = buildFallbackMatches();
    const cache: Record<string, Record<string, string>> = WorldCupApi.scoreCache;
    const keys: string[] = Object.keys(cache);
    if (keys.length === 0) return matches;

    for (let i = 0; i < matches.length; i++) {
      const m: MatchInfo = matches[i];
      const c: Record<string, string> | undefined = cache[m.id];
      if (c !== undefined) {
        m.homeScore = parseInt('' + c['hs']) || 0;
        m.awayScore = parseInt('' + c['as']) || 0;
        // ⚠️ status是联合类型，不能直接赋string变量！
        const cachedStatus: string = c['status'] || 'scheduled';
        if (cachedStatus === 'finished') {
          m.status = 'finished';
        } else if (cachedStatus === 'live') {
          m.status = 'live';
        } else {
          m.status = 'scheduled';
        }
        m.timeElapsed = c['elapsed'] || 'notstarted';
        // 解析射手列表（JSON字符串）
        const hsRaw: string = c['homeScorers'] || '';
        const asRaw: string = c['awayScorers'] || '';
        if (hsRaw.length > 0) m.homeScorers = JSON.parse(hsRaw) as string[];
        if (asRaw.length > 0) m.awayScorers = JSON.parse(asRaw) as string[];
      }
    }
    return matches;
  }

  // 刷新比分（API → 更新matches → 写入缓存）
  static async refreshScores(matches: MatchInfo[], context?: object): Promise<void> {
    const data: Object | null = await tryFetchJson('/get/games');
    if (data === null) return;
    let changed: boolean = false;
    try {
      // ... 解析API数据，更新matches ...
      // 更新内存缓存（⚠️ status是联合类型，用m.status赋值）
      WorldCupApi.scoreCache[m.id] = {
        'hs': hsStr,
        'as': asStr,
        'status': m.status,
        'elapsed': m.timeElapsed,
        'homeScorers': JSON.stringify(m.homeScorers),
        'awayScorers': JSON.stringify(m.awayScorers)
      };
      changed = true;
    } catch (_e) { /* ignore */ }
    // 持久化到本地（传了context才保存）
    if (changed && context !== undefined) {
      await WorldCupApi.saveToPersistence(context);
    }
  }
}
```

### 页面层（加载顺序）

```typescript
async aboutToAppear(): Promise<void> {
  try {
    this.ctx = getContext(this) as common.UIAbilityContext;
    // 1. 先加载本地缓存（秒级）
    await WorldCupApi.loadPersistedCache(this.ctx);
    // 2. 拼装赛程+缓存比分（0网络）
    this.matches = WorldCupApi.getMatches();
    this.isLoading = false;  // 立即显示
    // 3. API刷新最新比分（后台）
    await WorldCupApi.refreshScores(this.matches, this.ctx);
    // 4. 启动自动刷新定时器
    this.startAutoRefresh();
  } catch (e) {
    this.loadError = true;
    this.isLoading = false;
  }
}
```

## 缓存结构设计

```json
// preferences key: "wc26_cache" → "scores"
{
  "1": {
    "hs": "2", "as": "0",
    "status": "finished", "elapsed": "FT",
    "homeScorers": "[\"J. Quinones\",\"R. Jimenez\"]",
    "awayScorers": "[]"
  },
  "5": {
    "hs": "0", "as": "1",
    "status": "finished", "elapsed": "FT",
    "homeScorers": "[]",
    "awayScorers": "[\"J. McGinn\"]"
  }
}
```

**设计要点：**
- 缓存所有比赛（包括scheduled的0:0），不只是finished
- `status`和`elapsed`一起缓存，这样打开APP就知道哪些是live
- 射手列表用`JSON.stringify`序列化为字符串存储
- 用`Record<string, Record<string, string>>`而非`Map`（ArkTS运行时Map不可靠）

## 两层缓存架构

| 层级 | 存储位置 | 生命周期 | 访问速度 |
|------|---------|---------|---------|
| 内存缓存 | `static scoreCache` | 当前会话 | 0ms |
| 持久化缓存 | `preferences` | 跨会话 | ~50ms |

- 内存缓存：`getMatches()`直接读，0延迟
- 持久化缓存：`loadPersistedCache()`从preferences加载到内存，~50ms
- API调用：`refreshScores()`获取最新数据，更新两层缓存

## 注意事项

1. **必须传context**：`preferences.getPreferences`需要`UIAbilityContext`，纯函数里拿不到
2. **只在数据变化时持久化**：用`changed`标志避免无意义的写入
3. **缓存结构要简单**：用`Record<string, Record<string, string>>`，不要嵌套太深
4. **首次打开无缓存**：`getMatches()`返回的全是0:0 scheduled，API刷新后才更新
5. **手动清缓存**：开发时如果缓存结构变了，需要手动清除preferences（卸载APP或改STORE_NAME）
