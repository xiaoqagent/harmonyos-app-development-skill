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
  {id:'1', home:'Mexico', away:'South Africa', group:'A', kickoff:'06/12 04:00'},
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

### 页面层（所有页面统一改法）

```ets
// ❌ 旧写法——阻塞
async aboutToAppear(): Promise<void> {
  this.matches = await WorldCupApi.fetchMatches();
  this.isLoading = false;
}

// ✅ 新写法——秒加载
aboutToAppear(): void {
  this.matches = WorldCupApi.getMatches();  // 同步，0ms
  this.isLoading = false;                   // 立即显示
  WorldCupApi.refreshScores(this.matches);  // 异步，不加await
}
```

## 注意事项

1. **不加await**：`refreshScores()` 不加await，让它在后台跑
2. **引用类型**：`matches` 是 `@State` 数组，`refreshScores` 修改元素属性后，ArkUI自动感知并刷新UI
3. **所有页面统一**：SchedulePage、MainPage、PredictionPage、BracketPage、TopScorerPage 都要改
4. **删除旧方法**：`fetchMatches()` 方法可以删除，避免遗留引用

## 效果

- 首屏加载：3-4秒 → 瞬间（0ms网络等待）
- 比分刷新：后台1-2秒后自动更新（用户无感知）
- 离线可用：API挂了也能显示赛程（0:0 scheduled）
