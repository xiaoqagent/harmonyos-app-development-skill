# API数据离线兜底模式

## 问题

APP依赖外部API（如体育赛事数据），API可能因网络问题、限流、SSL错误而不可用。此时所有页面显示空数据。

## 方案：hardcoded骨架 + API动态数据按ID合并

### 1. 队伍数据兜底（ALL_TEAMS）

硬编码全部48支队伍的中文名、国旗URL、FIFA代码到 `const ALL_TEAMS` 数组中。API失败时自动加载离线数据：

```typescript
interface FallbackTeamData {
  id: string;
  name_en: string;
  name_cn: string;
  flag: string;
  fifa: string;
}

const ALL_TEAMS: FallbackTeamData[] = [
  {id:'1', name_en:'Mexico', name_cn:'墨西哥', flag:'https://flagcdn.com/w80/mx.png', fifa:'MEX'},
  // ... 全部48队
];

// API优先，失败时用硬编码
async function ensureTeamsLoaded(): Promise<void> {
  if (teamsCache.length > 0) return;
  const data = await tryFetchJson('/get/teams');  // 先试API
  if (data !== null) {
    // API成功，使用API数据
    teamsCache = arr;
    return;
  }
  loadFallbackTeams();  // API失败，硬编码兜底
}
```

### 2. 已结束比赛比分兜底（FALLBACK_SCORES）

对于已经结束的比赛，硬编码最终比分和进球者，保证APP离线时也显示正确比分和射手榜。

```typescript
interface FallbackScoreData {
  hs: number;       // 主队比分
  as: number;       // 客队比分
  status: string;   // 'finished' | 'scheduled' | 'live'
  elapsed: string;  // 'FT' | 'notstarted'
  homeS: string[];  // 主队进球者（含时间标记）
  awayS: string[];  // 客队进球者
}

const FALLBACK_SCORES: Record<string, FallbackScoreData> = {
  '1': {hs:2, as:0, status:'finished', elapsed:'FT',
        homeS:['F. Balogun 31\'', 'F. Balogun 45\'+5\''] as string[], awayS:[] as string[]},
  // ...
};
```

**注意**：进球者字符串包含 `'`（分钟标记），在ArkTS中需要用 `\'` 转义。

### 3. 在 buildFallbackMatches 中应用

```typescript
function buildFallbackMatches(): MatchInfo[] {
  // ... 从SCHEDULE构建基本数据 ...
  applyFallbackScores(result);  // 应用硬编码比分
  return result;
}

function applyFallbackScores(matches: MatchInfo[]): void {
  for (let i = 0; i < matches.length; i++) {
    const c = FALLBACK_SCORES[matches[i].id];
    if (c !== undefined) {
      matches[i].homeScore = c.hs;
      matches[i].awayScore = c.as;
      matches[i].status = c.status;   // 'finished' → 射手榜可提取
      matches[i].homeScorers = c.homeS;
      matches[i].awayScorers = c.awayS;
    }
  }
}
```

## 北美体育赛事时区换算

### 问题

API 返回的 `local_date` 是场馆当地时间。美加墨三国横跨多个时区：

| 地区 | 夏令时UTC偏移 | 到北京时间的偏移 |
|------|-------------|----------------|
| 美国东部 (EDT) | UTC-4 | +12h |
| 美国中部 (CDT) | UTC-5 | +13h |
| 美国山地 (MDT) | UTC-6 | +14h |
| 美国太平洋 (PDT) | UTC-7 | +15h |
| 墨西哥城 (CST) | UTC-6 | +14h |
| 温哥华 (PDT) | UTC-7 | +15h |
| 多伦多 (EDT) | UTC-4 | +12h |

### 正确做法

**不要用固定偏移**。不同场馆在不同时区，固定+15h（原做法）会导致大多数比赛时间错误。

**推荐方案**：
1. 使用外部权威来源（如 worldcup2026cn.com、CCTV5节目表）获取准确的北京时间
2. 硬编码所有比赛的 kickoff 时间到 SCHEDULE 数组
3. `toBeijingTime()` 只作为备选，用于淘汰赛等未硬编码的比赛

### 从网站爬取赛程数据

当需要获取外部赛程数据时（如CCTV5节目表无法直接API获取），可以用浏览器视觉模型读取：

```typescript
// 步骤：
// 1. browser_navigate(url)
// 2. browser_scroll('down') - 滚动到表格位置
// 3. browser_vision({question: '列出所有比赛的日期、北京时间、对阵'})
// 4. 从视觉分析结果中提取正确的北京时间和匹配
```
