# WorldCup2026 项目模式参考

## 项目概况

- **包名**: `WorldCup.xiaoq.profile`（AGC注册）
- **版本**: v1.3.0 (versionCode 1000130)
- **页面**: 6个（MainPage + 5个功能页：赛程/积分榜/射手榜/晋级图/预测）
- **数据源**: 硬编码赛程骨架 + API动态比分（worldcup26.ir）+ 本地缓存
- **签名**: 复用xiaoq.p12 + WorldCup.debug.profileDebug.p7b
- **API**: `https://worldcup26.ir/get/games`（72场小组赛）、`/get/teams`（48队）、`/get/groups`（积分榜）

## 数据架构（三层）

```
getMatches()       → 硬编码72场赛程 + 内存缓存比分 → 同步，0ms
refreshScores()    → API拉最新比分 → 更新matches + 写入内存缓存 + 持久化到preferences
loadPersistedCache → 启动时从preferences读取上次缓存 → ~50ms
```

**关键**：已完赛的比分存本地缓存，第二次打开APP秒出结果，不再请求API。

## 赛程数据来源

硬编码72场赛程，时间来自官方赛程图（北京时间UTC+8）。**不用API的local_date做时区转换**——API时间因比赛地点不同而不同，固定偏移不可能对所有比赛都正确。

```typescript
const SCHEDULE: MatchRaw[] = [
  {id:'1',home:'Mexico',away:'South Africa',group:'A',kickoff:'06/12 03:00',matchday:'1'},
  // ... 72场，ID严格对齐API返回的id字段
];
```

**ID对齐铁律**：hardcoded的ID必须从API实际返回数据中逐条提取，不能自己推导。WorldCup2026踩坑：按组排ID vs API按时间排ID，导致比分全部串位。

## 比分合并（merge-by-ID）

```typescript
static async refreshScores(matches: MatchInfo[], context?: object): Promise<void> {
  const data = await tryFetchJson('/get/games');
  if (data === null) return;
  // 建立API索引
  const apiMap: Record<string, Record<string, string>> = {};
  for (let i = 0; i < games.length; i++) {
    apiMap[g['id']] = g;
  }
  // 按ID合并到matches（引用类型，修改后UI自动更新）
  for (let i = 0; i < matches.length; i++) {
    const g = apiMap[matches[i].id];
    if (g !== undefined) {
      matches[i].homeScore = parseInt('' + g['home_score']) || 0;
      // ... status用if/else赋字面量（联合类型不能赋string变量）
    }
  }
  // 持久化到本地
  if (context !== undefined) await saveToPersistence(context);
}
```

## 射手榜实时提取

从已完赛的match数据中统计进球数，按进球数降序排列。中英文名映射：

```typescript
private static readonly SCORER_CN: Record<string, string> = {
  'F. Balogun': '巴洛贡', 'V. Júnior': '维尼修斯', 'Breel Embolo': '恩博洛',
  // ... 所有已知射手
};
// 显示格式：'巴洛贡 F. Balogun'（中文在前，英文在后）
```

## 预测模块设计

### 日期降级逻辑（getNextAvailableMatches）

明天没有比赛时，自动找最近的未来比赛日。必须同时过滤status：

```typescript
if (match.kickoff.indexOf(tomorrowStr) >= 0 && match.status === 'scheduled')
```

### 弹窗必须用Stack做根节点

PredictionPage的build()用Stack，PredictDialog作为Stack的第二层子节点覆盖在主内容上。不能嵌套在Column内部（会被布局约束裁剪）。

### 注册昵称必填 + 排行榜隐私

排行榜只显示昵称不显示手机号。注册时`nicknameInput.length === 0`直接return。

## 自动刷新（isRefreshing锁）

3秒间隔，最多7次（~21秒），防请求堆积：

```typescript
if (!this.isRefreshing) {
  this.isRefreshing = true;
  WorldCupApi.refreshScores(this.matches, this.ctx).then(() => {
    this.isRefreshing = false;
  }).catch(() => { this.isRefreshing = false; });
}
```

## 本地缓存（preferences两层架构）

内存缓存（static scoreCache）+ 持久化缓存（preferences `wc26_cache`）。

`refreshScores()`传context时自动持久化；`getMatches()`读内存缓存。

详见 `references/local-data-cache-pattern.md`。

## 版本号管理

MainPage定义 `private readonly APP_VERSION: string = '1.3.0'`，显示在预测界面"进入预测"按钮下方。同步更新 `app.json5` 的 `versionCode` 和 `versionName`。

⚠️ **版本号必须在所有UI分支都显示**：卸载重装后用户数据清空，页面会进「未注册」分支。如果版本号只在「已注册」分支显示，用户看不到。规则：版本号放在条件分支之外，或每个分支内都放一份。

⚠️ **版本号三处同步**：`app.json5`(versionName) + `app.json5`(versionCode, 每次+10) + `MainPage.ets`(APP_VERSION常量)。漏改任何一个都会导致显示不一致。

## 各页面刷新策略一览

| 页面 | 刷新方式 | 实现 |
|------|---------|------|
| **SchedulePage** | setInterval 3s×7次 + isRefreshing锁 | 自动，有live比赛持续刷 |
| **BracketPage** | setInterval 3s×7次 + isRefreshing锁 | 自动，与SchedulePage同策略 |
| **StandingPage** | Refresh下拉刷新 + 页面打开自动fetch | 手动下拉 + 每次进入页面自动拉 |
| **TopScorerPage** | await refreshScores + loadScorerNames | 打开时刷新比分+远程射手名映射 |
| **PredictionPage** | 同步骨架然后后台异步refreshScores + autoCalculateScores | 打开时秒显示，后台刷 |

## 预测积分系统

### 计分规则
- 猜对胜负（主胜/平/客胜）：**+1分**
- 猜对比分（精确匹配）：**+3分**（含胜负分，共4分）

### ⚠️ calculateScore从未被调用（v1.3.0修复）

`UserStore.calculateScore()` 方法写好了完整的计分逻辑，但整个项目没有任何地方调用它。预测记录永远显示「待开赛」。

**修复**：在PredictionPage新增 `autoCalculateScores()` 方法：
```typescript
private async autoCalculateScores(): Promise<void> {
  for (let i = 0; i < this.allMatches.length; i++) {
    const m: MatchInfo = this.allMatches[i];
    if (m.status === 'finished') {
      await UserStore.calculateScore(getContext(this), m.id, m.homeScore, m.awayScore);
    }
  }
  await this.loadUserData(); // 计分后重新加载
}
```

调用时机：`aboutToAppear` 中，`await refreshScores()` → `loadUserData()` → `autoCalculateScores()`。

### ⚠️ refreshScores必须await（v1.3.0修复）

原来 `aboutToAppear` 中 `WorldCupApi.refreshScores(this.allMatches)` 没有await，导致下一行 `loadUserData()` 读取预测记录时，比赛比分数据还是旧的。

**规则**：凡是依赖 `refreshScores` 更新后的数据的逻辑，必须 `await refreshScores()` 后再执行。

### ⚠️ @State不检测数组元素属性修改（v1.4.6修复）

ArkTS 的 `@State` 只检测数组引用是否变化，**不检测数组中对象属性的就地修改**。`refreshScores()` 内部执行 `m.homeScore = hs` 这种修改后，`@State matches` 感知不到变化，UI不刷新。

**每次 `refreshScores` 修改完matches后，必须重新赋值数组引用：**

```typescript
await WorldCupApi.refreshScores(this.matches, this.ctx);
this.matches = [...this.matches];  // 重新赋值触发 @State 更新
```

同样适用于自动刷新的回调中：

```typescript
WorldCupApi.refreshScores(this.matches, this.ctx).then(() => {
  this.isRefreshing = false;
  this.matches = [...this.matches];  // 触发UI刷新
}).catch(() => {
  this.isRefreshing = false;
});
```

**不这么做的后果**：API正常返回数据，`refreshScores` 正确更新了内存中的match对象的score/status字段，但页面显示始终不变（永远显示0:0）。

**适用范围**：所有页面（MainPage、SchedulePage、BracketPage、PredictionPage）中 `refreshScores` 调用后都必须加 `this.matches = [...this.matches]`。

### ⚠️ aboutToAppear不要阻塞UI（v1.4.3修复）

当页面需要同时加载本地数据（快）和API数据（慢）时，`aboutToAppear` 不能串行await：

```typescript
// ❌ 错误——串行阻塞UI，需等API返回后才显示
async aboutToAppear(): Promise<void> {
  this.allMatches = WorldCupApi.getMatches();  // 同步，0ms
  this.isLoading = false;
  await WorldCupApi.refreshScores(this.allMatches);  // 3-5秒
  await this.loadUserData();  // 本地，~50ms
}

// ✅ 正确——同步骨架先显示，API后台刷新
aboutToAppear(): void {
  // 同步骨架秒显示
  this.allMatches = WorldCupApi.getMatches();
  this.isLoading = false;
  // 后台异步刷（不阻塞UI）
  WorldCupApi.refreshScores(this.allMatches).then(async () => {
    this.allMatches = [...this.allMatches];
    await this.autoCalculateScores();
  }).catch((_e: Error) => {
    // API失败，用缓存数据兜底
  });
}
```

**关键变化**：
- `async aboutToAppear(): Promise<void>` → `aboutToAppear(): void`（去掉async，页面渲染不被阻塞）
- 本地数据通过 `.then()` 链异步加载
- API刷新放在后台，页面先显示骨架数据

### ⚠️ Promise.catch需要显式类型标注

ArkTS严格模式下，Promise的`.catch()`回调参数不能是隐式的`any`类型：

```typescript
// ❌ 编译报错：Use explicit types instead of "any", "unknown"
.catch((_e) => { ... })

// ✅ 正确：显式标注 Error 类型
.catch((_e: Error) => { ... })
```

这个规则适用于所有Promise链中的`.catch()`和Promise构造函数中的`reject`回调。

## 下拉刷新（Refresh组件）

积分榜使用ArkTS的Refresh组件实现下拉刷新：

```typescript
@State isRefreshing: boolean = false;

Refresh({ refreshing: $$this.isRefreshing }) {
  Column() {
    // 内容...
  }
  .width('100%').height('100%')
}
.onRefreshing(() => { this.onRefresh(); })
.width('100%').layoutWeight(1)
```

⚠️ Refresh组件内部的Column必须设 `.height('100%')`，否则下拉手势检测不到。
⚠️ `$$this.isRefreshing` 是**双向绑定**（`$$` 是关键），框架自动控制下拉动画的起止。

## 远程配置数据加载（scorer_names模式）

当数据需要远程更新（如射手名中文映射），不用发版：

```
APP启动
  ↓
① 内存中的硬编码映射（代码兜底）
  ↓
② 本地缓存（preferences）→ 合并覆盖
  ↓
③ 远程拉取 JSON → 成功则更新缓存 + 合并到内存
```

**远程请求用完整URL直接请求**，不走 `tryFetchJson`（它会拼接 `API_BASE`）：

```typescript
private static readonly REMOTE_URL: string = 'https://xiaoq.xiao-q.com/api/scorer_names';

static async loadRemoteData(context?: object): Promise<void> {
  // 1. 读本地缓存
  if (context !== undefined) {
    const store = await preferences.getPreferences(ctx, 'wc26_cache');
    const cached = JSON.parse(await store.get('key', '{}'));
    // merge into working map
  }
  // 2. 远程更新（用http直接请求完整URL）
  const req = http.createHttp();
  try {
    const resp = await req.request(REMOTE_URL, {
      method: http.RequestMethod.GET,
      connectTimeout: 5000, readTimeout: 10000,
      expectDataType: http.HttpDataType.OBJECT
    });
    if (resp.responseCode === 200) {
      // merge remote data into working map
      // persist to preferences
    }
  } catch (_e) { /* 远程不可用，用内置兜底 */ }
  finally { req.destroy(); }
}
```

**自动更新**：cron每天跑Python脚本，从API采集新数据→LLM翻译→写入JSON。详见服务器端 `update_scorer_names.py`。

## 踩坑记录

1. **API ID顺序不一致**: 硬编码按组排 vs API按时间排，比分全串位→从API逐条提取ID
2. **API时间不准**: local_date时区因地点不同，+15h偏移对某些比赛差3小时→硬编码官方时间
3. **http.HttpDataType.OBJECT自动转换**: "TRUE"→boolean true, "2"→number 2→用`'' + value`转字符串
4. **联合类型赋值**: `m.status = string变量` 编译报错→用if/else赋字面量
5. **弹窗被Column裁剪**: PredictDialog嵌在Column内部不显示→改Stack根节点
6. **interface在函数体内**: 编译报错→移到模块级
7. **read_file行号前缀**: execute_code中read_file返回`N|content`，写回文件导致1853个Error
8. **请求堆积**: 500ms无锁setInterval发API→3s+isRefreshing锁
9. **calculateScore从未被调用**: 计分逻辑写好了但项目里没有任何地方调用→PredictionPage打开时自动遍历已完赛比赛调用
10. **refreshScores没await**: 后台异步跑，下一行loadUserData读到旧数据→加await确保顺序
11. **版本号只在已注册分支显示**: 卸载重装后用户数据清空，进未注册分支看不到版本→所有分支都放版本号
12. **下拉刷新不生效**: Refresh内部Column没设height('100%')→下拉手势检测不到
14. **release签名直装失败**: 9568322错误→release包只能通过应用市场分发，不能hdc直装
15. **签名不一致覆盖安装**: 9568332错误→先hdc shell bm uninstall卸载旧版再装
16. **AGC API Level限制**: compatibleSdkVersion必须≤22(`6.0.2(22)`)→降compatibleSdkVersion，保持targetSdkVersion高版本
17. **射手名重复显示**: `getScorerCnName`找不到映射时返回英文名本身→拼接格式`cn+en`变成`K. Havertz K. Havertz`→修复：找不到时返回空字符串，显示逻辑判断cnName.length>0再拼接
18. **版本号只在已注册分支显示**: 卸载重装后用户数据清空→进未注册分支看不到版本号→版本号必须在所有UI分支（注册/未注册/错误）都显示
19. **TopScorerPage refreshScores没await**: 比分更新前提取射手榜→缓存显示旧数据→加await，刷新完成后重新extractTopScorers更新UI
20. **比赛时间计算错误 → 改用权威源爬取**: 首次用+12h偏移算错瑞士vs波黑时间(06/19 00:00→实际03:00)，第二次再用+15h也错。正确的做法：直接爬取 `worldcup2026cn.com/schedule/` 上的北京时间赛程表，而非从API推算。
21. **队伍名显示"队伍N"**: `/get/teams` API限流=空缓存→`findTeamNameById`返回"队伍"+ID→硬编码48队ALL_TEAMS，API失败时 `loadFallbackTeams()` 兜底
22. **比分和射手全空**（连锁故障）: API限流→`refreshScores`不执行→所有match保持scheduled→`extractTopScorers`检查status===finished为空→加 `FALLBACK_SCORES` 硬编码已结束比赛比分+射手，`buildFallbackMatches` 中直接应用
23. **预测页底部被遮挡**: List底padding 8→24→100→150vp才够（独立页面无TabBar但虚拟按键占空间）<br>**规则**：有TabBar的页面List給 `bottom: 56`（TabBar高度），独立页面List給 `bottom: 150`
24. **Promise.catch需要显式类型标注**: `.catch((_e) => {})` 在ArkTS编译时报 `arkts-no-any-unknown` → 改为 `.catch((_e: Error) => {})`

