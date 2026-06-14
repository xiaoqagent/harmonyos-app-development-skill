# ArkTS 对象字面量类型转换失败的解决方案

## 问题

ArkTS 严格模式下，对象字面量 `as Type` 转换可能失败：

```
Conversion of type '{ winner: undefined; }' to type 'BracketMatch' may be a mistake
because neither type sufficiently overlaps with the other.
```

原因：`undefined` 和 `null` 是不同类型，对象字面量中的属性类型必须与接口完全匹配。

## 解决方案

### 方案1：用工厂函数构建数据（推荐）

```typescript
// ❌ 一行写完，类型不匹配时 as Type 失败
const matches: BracketMatch[] = [
  { matchId: 'R16-1', winner: null, penaltyScore: null } as BracketMatch  // 可能失败
];

// ✅ 工厂函数，逐字段赋值
function buildBracket(): BracketMatch[] {
  const list: BracketMatch[] = [];
  list.push({
    matchId: 'R16-1',
    stage: 'round16',
    position: 1,
    homeTeam: MOCK_TEAMS['ARG'],
    awayTeam: MOCK_TEAMS['ENG'],
    homeScore: 3,
    awayScore: 1,
    winner: MOCK_TEAMS['ARG']   // TeamInfo | null → 用 null
  } as BracketMatch);
  return list;
}
```

### 方案2：省略 undefined 字段

```typescript
// ❌ penaltyScore 类型是 string | undefined，不能赋 null
{ penaltyScore: null }  // Type 'null' is not comparable to type 'string | undefined'

// ✅ 不写该字段，默认就是 undefined
{ /* penaltyScore 不写 */ }
// 或显式
{ penaltyScore: undefined }
```

### 方案3：先构建再赋值

```typescript
const match: BracketMatch = {
  matchId: 'R16-1',
  stage: 'round16',
  position: 1,
  homeTeam: MOCK_TEAMS['ARG'],
  awayTeam: MOCK_TEAMS['ENG'],
  homeScore: 3,
  awayScore: 1,
  winner: MOCK_TEAMS['ARG']
} as BracketMatch;
// penaltyScore 不写 → undefined ✅
```

## null vs undefined 规则速查

| 接口定义 | 正确赋值 | 错误赋值 |
|----------|----------|----------|
| `winner: TeamInfo \| null` | `null` 或 `TeamInfo` | `undefined` |
| `penaltyScore?: string` | 不写 或 `string` | `null` |
| `homeTeam: TeamInfo \| null` | `null` 或 `TeamInfo` | `undefined` |

## 非标准JSON字符串解析

有些API返回的JSON格式不标准，如进球者数据：

```json
{"home_scorers": "{\"J. Quiñones 9'\",\"R. Jiménez 67'\"}"}
```

这不是合法JSON（用了花括号包裹逗号分隔的带引号字符串）。解析方式：

```typescript
function parseScorers(scorersStr: string): string[] {
  if (!scorersStr || scorersStr === 'null') return [];
  try {
    // 转换为合法JSON数组
    const cleaned: string = scorersStr
      .replace(/^\{/, '[')
      .replace(/\}$/, ']')
      .replace(/'/g, '"');
    return JSON.parse(cleaned) as string[];
  } catch (e) {
    return [scorersStr];  // 解析失败返回原始字符串
  }
}
```
