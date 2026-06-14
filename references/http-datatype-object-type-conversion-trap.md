# http.HttpDataType.OBJECT 类型自动转换陷阱

## 问题

`expectDataType: http.HttpDataType.OBJECT` 会自动将JSON值转为原生类型：
- `"2"` (string) → `2` (number)
- `"TRUE"` (string) → `true` (boolean)
- `"finished"` (string) → `"finished"` (string，不变)

但ArkTS的类型系统仍然认为这些值是 `string`（因为 `Record<string, string>` 的签名）。

## 错误模式

```ets
const g: Record<string, string> = apiData as Record<string, string>;

// ❌ 对number值做parseInt——行为不可预测
m.homeScore = parseInt(g['home_score']) || 0;  // parseInt(2) on number 2

// ❌ 对boolean值做字符串比较——永远false
const finished: string = g['finished'] || '';  // runtime: boolean true
if (finished === 'TRUE') { ... }  // true !== 'TRUE' → false!

// ❌ as 类型断言——编译期only，运行时不生效
const score: number = g['home_score'] as number;  // 编译过，运行时仍是string类型签名
```

## 正确做法

用 `'' + value` 强制转字符串，再检查所有可能的值：

```ets
// 比分——number或string都转成string再parseInt
const hsStr: string = '' + g['home_score'];  // number 2 → "2", string "2" → "2"
m.homeScore = parseInt(hsStr) || 0;

// 布尔——boolean true或string "TRUE"都覆盖
const finStr: string = '' + g['finished'];  // boolean true → "true", string "TRUE" → "TRUE"
const isFinished: boolean = (finStr === 'true' || finStr === 'TRUE');

// 时间——统一转字符串
const elapsed: string = '' + g['time_elapsed'];
```

## 规则

从 `http.HttpDataType.OBJECT` 返回的数据，**永远用 `'' + value` 转字符串后再处理**。
不要信任 `as string` / `as number` / `as boolean` 断言——ArkTS运行时的类型断言不改变实际值的类型。
