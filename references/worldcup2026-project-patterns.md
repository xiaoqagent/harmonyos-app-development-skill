# WorldCup2026 项目模式参考

## 项目概况

- **包名**: `WorldCup.xiaoq.profile`（AGC注册）
- **版本**: v1.2.0 (versionCode 1000120)
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

MainPage定义 `private readonly APP_VERSION: string = '1.2.0'`，显示在预测界面"进入预测"按钮下方。同步更新 `app.json5` 的 `versionCode` 和 `versionName`。

## 踩坑记录

1. **API ID顺序不一致**: 硬编码按组排 vs API按时间排，比分全串位→从API逐条提取ID
2. **API时间不准**: local_date时区因地点不同，+15h偏移对某些比赛差3小时→硬编码官方时间
3. **http.HttpDataType.OBJECT自动转换**: "TRUE"→boolean true, "2"→number 2→用`'' + value`转字符串
4. **联合类型赋值**: `m.status = string变量` 编译报错→用if/else赋字面量
5. **弹窗被Column裁剪**: PredictDialog嵌在Column内部不显示→改Stack根节点
6. **interface在函数体内**: 编译报错→移到模块级
7. **read_file行号前缀**: execute_code中read_file返回`N|content`，写回文件导致1853个Error
8. **请求堆积**: 500ms无锁setInterval发API→3s+isRefreshing锁
