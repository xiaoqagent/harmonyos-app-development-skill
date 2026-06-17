# 秒加载 + 异步刷新模式（Instant Load + Async Refresh）

## 问题

`await fetchAPI()` 在 `aboutToAppear` 中阻塞UI渲染，导致页面白屏3-4秒。

## 方案

拆成两个方法：
- `getMatches()` — 同步，返回硬编码骨架数据，0毫秒
- `refreshScores(matches)` — 异步，后台调API刷新动态数据

## 实现

### API层（WorldCupApi.ets）

```ets
// 硬编码骨架数据
const SCHEDULE: MatchRaw[] = [
  {id:'1', home:'Mexico', away:'South Africa', group:'A', kickoff:'06/12 03:00'},
  // ... 全部数据
];

function buildFallbackMatches(): MatchInfo[] {
  const result: MatchInfo[] = [];
  for (let i = 0; i < SCHEDULE.length; i++) {
    const s: MatchRaw = SCHEDULE[i];
    result.push({
      id: s.id,
      homeTeam: makeTeam(s.home, s.group),
      awayTeam: makeTeam(s.away, s.group),
      homeScore: 0, awayScore: 0,
      status: 'scheduled',
      kickoff: s.kickoff,
      // ...
    } as MatchInfo);
  }
  return result;
}

export class WorldCupApi {
  // 同步——秒返
  static getMatches(): MatchInfo[] {
    return buildFallbackMatches();
  }

  // 异步——后台刷比分
  static async refreshScores(matches: MatchInfo[]): Promise<void> {
    const data: Object | null = await tryFetchJson('/get/games');
    if (data === null) return;
    try {
      const obj: Record<string, Object> = data as Record<string, Object>;
      const games: Object[] = obj['games'] as Object[];
      if (games === undefined) return;

      // 建立ID索引（用Record，不用Map——ArkTS运行时Map不可靠）
      const apiMap: Record<string, Record<string, string>> = {};
      for (let i = 0; i < games.length; i++) {
        const g: Record<string, string> = games[i] as Record<string, string>;
        apiMap[g['id']] = g;
      }

      // 合并到matches（引用类型，修改后@State自动刷新UI）
      for (let i = 0; i < matches.length; i++) {
        const m: MatchInfo = matches[i];
        const g: Record<string, string> | undefined = apiMap[m.id];
        if (g !== undefined) {
          // ⚠️ http.HttpDataType.OBJECT 会自动转类型！
          // "2" → number 2, "TRUE" → boolean true
          // 必须用 '' + value 强制转字符串
          const hsStr: string = '' + g['home_score'];
          const asStr: string = '' + g['away_score'];
          m.homeScore = parseInt(hsStr) || 0;
          m.awayScore = parseInt(asStr) || 0;

          const finStr: string = '' + g['finished'];
          const isFinished: boolean = (finStr === 'true' || finStr === 'TRUE');
          const elapsed: string = '' + g['time_elapsed'];

          if (isFinished) {
            m.status = 'finished';
            m.timeElapsed = 'FT';
          } else if (elapsed !== 'notstarted' && elapsed !== 'finished' && elapsed.length > 0) {
            m.status = 'live';
            m.timeElapsed = elapsed;
          }
        }
      }
    } catch (_e) { /* ignore */ }
  }
}
```

## 简单模式（fire-and-forget）

适用于只需要显示骨架+后台刷比分，无后续依赖的场景。

```ets
aboutToAppear(): void {
  this.matches = WorldCupApi.getMatches();  // 同步，0ms
  this.isLoading = false;                   // 立即显示
  WorldCupApi.refreshScores(this.matches);  // 异步，不加await
}
```

**关键**：
1. 不加await：`refreshScores()` 不加await，让它在后台跑
2. 引用类型：`matches` 是 `@State` 数组，`refreshScores` 修改元素属性后，ArkUI自动感知并刷新UI
3. 所有页面统一：SchedulePage、MainPage、PredictionPage、BracketPage、TopScorerPage 都要改
4. 删除旧方法：`fetchMatches()` 方法可以删除，避免遗留引用

## 复杂链式模式（.then() chains）

适用于需要按顺序执行多个异步操作（本地缓存→UI→API→后处理）的场景。**此模式解决"点进去等13秒"的问题。**

### 问题场景

```
aboutToAppear() 需要依次完成：
  ① 读本地用户数据（Preferences，~50ms）
  ② 加载缓存预测记录（Preferences，~200ms）
  ③ 显示UI骨架
  ④ API刷新比分（~3s）
  ⑤ 自动计分（遍历所有已结束比赛，~5-10s）
```

如果用 `async aboutToAppear` + `await` 串行执行，用户要等 ①+④+⑤ 共 8-13 秒才能看到内容。

### 修复方案：拆成并行链

```ets
aboutToAppear(): void {
  // 链A: 本地数据加载（不阻塞UI）
  const ctx = getContext(this);
  UserStore.getCurrentUser(ctx).then(async (phone: string) => {
    if (phone.length > 0) {
      this.currentUser = phone;
      this.isRegistered = true;
      const nickname: string = await UserStore.getNickname(ctx, phone);
      if (nickname.length > 0) {
        this.currentNickname = nickname;
      }
      // 加载本地缓存的预测记录
      await this.loadUserData();
    }
  }).catch((_e: Error) => {
    // 用户未注册，忽略
  });

  // 链B: 同步骨架秒显示（独立于链A）
  this.allMatches = WorldCupApi.getMatches();
  this.isLoading = false;

  // 链C: API刷新+后处理（不阻塞链A和链B）
  WorldCupApi.refreshScores(this.allMatches).then(async () => {
    if (this.isRegistered) {
      // 比分刷新后才算分
      await this.autoCalculateScores();
    }
  }).catch((_e: Error) => {
    // API失败，用缓存数据兜底
  });
}
```

### 关键要点

1. **移除 `async` 关键字**：`aboutToAppear(): void` 改为同步函数，不再返回 Promise
2. **链式分离**：每个异步操作链独立通过 `.then()` 启动，互不阻塞
3. **本地数据先行**：Preference 本地操作（~50ms）先于 API 调用（~3s）
4. **骨架立显**：`this.isLoading = false` 放在所有 `.then()` 之前，页面立即渲染
5. **catch要有类型**：ArkTS严格模式要求 `catch((_e: Error) => {})` 不能省略 Error 类型

### 效果对比

| 模式 | 用户等待时间 | 首次内容显示 | 最终数据完整 |
|------|-------------|------------|------------|
| `async aboutToAppear` + 串行 await | 8-13秒 | 13秒后才显示 | 13秒后完整 |
| 同步 + `.then()` 链 | **<100ms** | 瞬间显示骨架 | 后台完成（无感知） |

## 注意事项

1. **不加await**：`refreshScores()` 不加await，让它在后台跑
2. **引用类型**：`matches` 是 `@State` 数组，`refreshScores` 修改元素属性后，ArkUI自动感知并刷新UI
3. **所有页面统一**：SchedulePage、MainPage、PredictionPage、BracketPage、TopScorerPage 都要改
4. **删除旧方法**：`fetchMatches()` 方法可以删除，避免遗留引用

## 效果

- 首屏加载：3-4秒 → 瞬间（0ms网络等待）
- 比分刷新：后台1-2秒后自动更新（用户无感知）
- 离线可用：API挂了也能显示赛程（0:0 scheduled）
