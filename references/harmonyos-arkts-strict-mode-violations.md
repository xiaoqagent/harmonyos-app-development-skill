# ArkTS Strict Mode Error Reference

Actual ArkTS compilation errors from the XiaoQ HarmonyOS chat app porting session. Each entry includes the error code, message, root cause, and fix.

## Error Group 1: Object Literal Violations

### `arkts-no-untyped-obj-literals` — Object literal must correspond to some explicitly declared class or interface

**Trigger**: Creating inline object literals without a type annotation.

**Example error (from HermesApi.ets:40)**:
```
Object literal must correspond to some explicitly declared class or interface (arkts-no-untyped-obj-literals)
```

**Fix**: Always annotate with explicit interface or `Record<string, Object>`:
```typescript
// ❌ Bad - typed by inference
const bodyObj = { model: 'current', stream: false };

// ✅ Good - explicit type
const bodyObj: Record<string, Object> = {
  'model': 'current',
  'stream': false
};
```

### Error Group 2: Throw Restrictions

### `arkts-limited-throw` — Throw statements cannot accept values of arbitrary types

**Trigger**: Catching and re-throwing, or throwing non-Error subclass instances.

**Example error (from HermesApi.ets:78)**:
```
"throw" statements cannot accept values of arbitrary types (arkts-limited-throw)
```

**Fix**: Create a custom Error subclass and use type guards:
```typescript
class HermesError extends Error {
  constructor(message: string) {
    super(message);
  }
}

// ✅ Safe re-throw pattern
catch (error) {
  if (error instanceof HermesError) {
    throw error;
  }
  if (error instanceof Error) {
    throw new HermesError((error as Error).message);
  }
  throw new HermesError('未知错误');
}
```

### Error Group 3: HttpRequest API

### Property does not exist on type 'HttpRequest'

**Trigger**: Calling `setRequestHeader()` on an HttpRequest object.

**Example error (from HermesApi.ets:36-38)**:
```
Property 'setRequestHeader' does not exist on type 'HttpRequest'
```

**Fix**: Headers go in the `request()` options `header` field, not via setter methods:
```typescript
// ❌ Bad - setRequestHeader doesn't exist
const httpRequest = http.createHttp();
httpRequest.setRequestHeader('Content-Type', 'application/json');

// ✅ Good - headers in request options
const response = await httpRequest.request(url, {
  method: http.RequestMethod.POST,
  header: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + apiKey
  },
  extraData: JSON.stringify(body),
  ...
});
```

### Error Group 4: @Builder Parameter Passing

### Argument not assignable

**Trigger**: Passing object literal to @Builder function.

**Example**:
```
Argument of type '{ message: ChatMessage; }' is not assignable to parameter of type 'ChatMessage'
```

**Fix**: Pass parameters directly, not wrapped in object literal:
```typescript
// ❌ Bad - wrapped in object
this.MessageBubble({ message: msg })

// ✅ Good - direct parameter
this.MessageBubble(msg)
```

### Error Group 5: Alignment Type Mismatch

### Argument of type 'ItemAlign' is not assignable to parameter of type 'HorizontalAlign'

**Trigger**: Using wrong alignment enum for a container.

**Fix**: Match alignment type to container orientation:
```typescript
// Column → HorizontalAlign (horizontal alignment within vertical container)
Column() { ... }
.alignItems(HorizontalAlign.Start)

// Row → VerticalAlign (vertical alignment within horizontal container)
Row() { ... }
.alignItems(VerticalAlign.Top)

// Also valid: Row's alignItems uses VerticalAlign
// For a Row, justifyContent controls horizontal, alignItems controls vertical
```

### Error Group 6: rcp Response.Property Names

### Property 'responseCode' does not exist on type 'Response'

**Trigger**: Using `response.responseCode` with rcp.Response (this property exists on `@kit.NetworkKit.http.HttpResponse`, not on `rcp.Response`).

**Fix**: rcp uses `statusCode` instead of `responseCode`:

```typescript
// ❌ Bad - responseCode is for @kit.NetworkKit.http
if (response.responseCode === 200)

// ✅ Good - rcp uses statusCode
if (response.statusCode === 200)
```

### Error Group 7: rcp toString() returns string | null

### Type 'string | null' is not assignable to type 'string'
  Type 'null' is not assignable to type 'string'

**Trigger**: Assigning `rcp.Response.toString()` result directly to a `string` variable. The rcp Response API returns `string | null`.

**Error example**:
```
Type 'string | null' is not assignable to type 'string'.
  Type 'null' is not assignable to type 'string'.
```

**Fix**: Use nullish coalescing operator `??` to provide a fallback:

```typescript
// ❌ Bad - may be null
const errorText: string = response.toString();

// ✅ Good - fallback for null
const errorText: string = response.toString() ?? '请求失败';
```

### Error Group 7: Function May Throw

### Function may throw exceptions. Special handling is required.

**Trigger**: Calling an API function that can throw without try-catch or `.catch()` handler.

**Fix**: Wrap in try-catch:
```typescript
// ❌ Bad
this.sendMessage();  // async function may throw

// ✅ Good
try {
  await this.sendMessage();
} catch (error) {
  // handle
}
```

`promptAction.showToast()` triggers this warning too. Either wrap it or accept the warning if it's in a UI callback where throwing won't crash the app.

### Error Group 8: null vs undefined — 完全不同的类型！

**核心规则**：在ArkTS严格模式下，`null` 和 `undefined` 是**完全不同的类型**，不能互换使用。

**类型匹配规则**：
- 接口定义 `T | null` → 只能用 `null`，不能用 `undefined`
- 接口定义 `T | undefined`（或 `?:` 可选属性）→ 只能用 `undefined` 或不写该字段，不能用 `null`
- 接口定义 `T | null | undefined` → 两者都可以

**典型错误**：
```
Conversion of type '{ ... winner: undefined; }' to type 'BracketMatch' may be a mistake.
Types of property 'winner' are incompatible.
  Type 'undefined' is not comparable to type 'TeamInfo | null'.
```

```
Types of property 'penaltyScore' are incompatible.
  Type 'null' is not comparable to type 'string | undefined'.
```

**修复方案**：

```typescript
interface BracketMatch {
  winner: TeamInfo | null;      // 可以是 null，不能是 undefined
  penaltyScore?: string;        // 类型是 string | undefined，不能赋 null
}

// ❌ 错误 — winner 类型是 TeamInfo | null，不能用 undefined
{ winner: undefined }

// ❌ 错误 — penaltyScore 类型是 string | undefined，不能用 null
{ penaltyScore: null }

// ✅ 正确 — winner 用 null
{ winner: null }

// ✅ 正确 — penaltyScore 不写该字段（默认 undefined）
{ matchId: 'R16-1', homeTeam: ..., awayTeam: ... }
// 或显式
{ penaltyScore: undefined }  // 但不写更简洁
```

**遇到复杂对象字面量的 `as Type` 转换失败时**：用工厂函数构建数据，避免一行写完所有字段：

```typescript
// ✅ 用函数构建，可以按条件省略字段
function buildBracket(): BracketMatch[] {
  const list: BracketMatch[] = [];
  list.push({ matchId: 'R16-1', homeTeam: team, awayTeam: team, homeScore: 3, awayScore: 1, winner: team } as BracketMatch);
  // penaltyScore 不写 → 默认 undefined → 符合 string | undefined
  list.push({ matchId: 'R16-2', homeTeam: team, awayTeam: team, homeScore: 2, awayScore: 2, penaltyScore: '4-3', winner: team } as BracketMatch);
  return list;
}
```

### Error Group 9: @Entry build() 必须单根节点

**错误**：
```
In an '@Entry' decorated component, the 'build' method can have only one root node, which must be a container component.
```

**触发**：`build()` 方法内有两个并列的顶层组件（如一个 `Column` 加一个 `if` 条件渲染的弹窗）。

**修复**：用 `Stack` 包裹所有内容：

```typescript
// ❌ 错误 — 两个并列根节点
build() {
  Column() { /* 主内容 */ }
  if (this.showDialog) {
    Column() { /* 弹窗 */ }
  }
}

// ✅ 正确 — Stack 单根节点
build() {
  Stack() {
    Column() { /* 主内容 */ }
    if (this.showDialog) {
      Column() { /* 弹窗遮罩 + 内容 */ }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000099')
    }
  }
  .width('100%')
  .height('100%')
}
```

### Error Group 10: `as Type` 断言 vs `: Type` 注解

对于复杂对象字面量（含可空字段），`as Type` 断言比 `: Type` 注解更可靠：

```typescript
// 有时 `: Type` 注解会报错但 `as Type` 不会
const match: BracketMatch = { ... } // 可能报错
const match = { ... } as BracketMatch // 通常通过

// 最安全：用工厂函数 + as Type
```

### Error Group 11: `arkts-no-standalone-this` — 静态方法中不能用 this

**错误**：
```
Using "this" inside stand-alone functions is not supported (arkts-no-standalone-this)
```

**触发**：在类的静态方法中调用 `this.method()`。

**修复**：用 `ClassName.method()` 替代：

```typescript
class WorldCupApi {
  static async fetchMatches(): Promise<MatchInfo[]> {
    if (teamsMap.size === 0) {
      await this.fetchTeams();         // ❌ arkts-no-standalone-this
      await WorldCupApi.fetchTeams();  // ✅ 用类名
    }
  }
}
```

### Error Group 12: `arkts-no-aliases-by-index` — 不支持索引访问类型

**错误**：
```
Indexed access types are not supported (arkts-no-aliases-by-index)
```

**触发**：使用 `Type['field']` 语法访问接口的字段类型。

**修复**：直接赋值，不使用索引访问：

```typescript
// ❌ 错误
stage: g.type as MatchInfo['stage'];

// ✅ 正确 — 直接赋值
stage: g.type;
```

### Error Group 13: Image 组件空 URL 崩溃

**症状**：APP 闪退，无编译错误（运行时崩溃）。

**触发**：`Image('')` 传入空字符串 URL。

**修复**：渲染前检查 URL 长度，用 `@Builder` 封装：

```typescript
@Builder
TeamFlag(flagUrl: string) {
  if (flagUrl.length > 0) {
    Image(flagUrl).width(24).height(16).objectFit(ImageFit.Contain)
  } else {
    Text('⚽').fontSize(16)  // emoji fallback
  }
}
```

### Error Group 14: Unicode 智能引号导致乱码

**症状**：从外部 API 获取的文字显示乱码，或 JSON.parse 失败。

**触发**：API 返回包含 Unicode 智能引号的数据：
- `'` (U+2018, LEFT SINGLE QUOTATION MARK)
- `'` (U+2019, RIGHT SINGLE QUOTATION MARK)
- `"` (U+201C, LEFT DOUBLE QUOTATION MARK)
- `"` (U+201D, RIGHT DOUBLE QUOTATION MARK)

**修复**：解析前替换所有智能引号为 ASCII 引号：

```typescript
let cleaned: string = rawString;
cleaned = cleaned.replace(/[\u2018\u2019\u201C\u201D']/g, '"');
cleaned = cleaned.replace(/^\{/, '[').replace(/\}$/, ']');
const parsed: Object = JSON.parse(cleaned);
```

**最佳实践**：对外部 API 数据做清洗时，将所有非 ASCII 字符替换为 ASCII 等价物。展示数据（如球员名字）也建议清理后使用纯 ASCII。

### Error Group 15: `for...of` / `for...in` / `.forEach()` — 运行时崩溃

**症状**：编译无错误，但APP启动后页面空白、数据不加载、或直接闪退。**这是最隐蔽的坑**——编译器不报错，运行时静默失败。

**触发**：使用 `for...of`、`for...in`、`.forEach()` 循环遍历数组或Map。

**根因**：ArkTS严格模式下，这些循环语法在运行时不被支持。编译器可能通过（取决于版本），但运行时会抛出未捕获的异常，导致 `aboutToAppear` 中的异步函数中断，`@State` 变量永远保持初始空值。

**受影响的典型模式**：
```ets
// ❌ 全部不行
for (const item of this.items) { ... }
for (const key in obj) { ... }
this.items.forEach((item: Item) => { ... });
myMap.forEach((value: Object, key: string) => { ... });

// 在 getter 中更隐蔽：
get filteredData(): Item[] {
  const result: Item[] = [];
  for (const item of this.items) {  // ❌ 编译过，运行崩
    if (item.active) result.push(item);
  }
  return result;
}
// ForEach(this.filteredData, ...) → 永远是空数组
```

**修复**：全部改为 `for (let i = 0; ...)` 索引循环：
```ets
// ✅ 唯一安全的循环方式
for (let i = 0; i < this.items.length; i++) {
  const item: Item = this.items[i];
  if (item.active) result.push(item);
}
```

**排查方法**：全项目搜索 `for\s*\(const` 和 `.forEach(`，全部替换。

### Error Group 16: `get` 属性访问器不可靠

**症状**：页面空白，数据不显示，但无编译错误。

**触发**：在 `@Component` 中使用 `get xxx(): Type` 属性访问器，尤其当访问器内部有循环逻辑时。

**修复**：改为普通方法 `getXxx(): Type`，在 `build()` 中用 `this.getXxx()` 调用：
```ets
// ❌ 不稳定
get filteredData(): Item[] { ... }
ForEach(this.filteredData, ...)

// ✅ 稳定
getFilteredData(): Item[] { ... }
ForEach(this.getFilteredData(), ...)
```

### Error Group 17: `Map` 类型运行时不可靠

**症状**：`Map.get()` 返回 `undefined`（即使key存在），`Map.forEach()` 不执行。

**触发**：使用 `new Map()` 创建Map并调用其方法。

**修复**：用数组模拟Map：
```ets
// ❌ 不可靠
const cache: Map<string, Object> = new Map();
cache.set('key', data);
const val = cache.get('key');  // 可能返回 undefined

// ✅ 用数组 + 手动查找
interface CacheEntry { id: string; data: Object; }
const cache: CacheEntry[] = [];
function findById(id: string): Object | null {
  for (let i = 0; i < cache.length; i++) {
    if (cache[i].id === id) return cache[i].data;
  }
  return null;
}
```

## General ArkTS Strict Mode Rules Summary

| Rule | Meaning | Fix |
|------|---------|-----|
| `arkts-no-untyped-obj-literals` | All object literals need explicit type | `: Record<string, T>` or defined interface |
| `arkts-limited-throw` | Only Error subclass instances can be thrown | Custom Error class + instanceof guard |
| `arkts-no-for-in` | No `for...in` loops | Use `for...of` or indexed for |
| No implicit any | Variables must be typed | `let x: string = ''` not `let x = ''` |
| Catch variable is unknown | `catch(error)` - error type is unknown | `error instanceof Error` check before use |
| No dynamic import | No `import()` expressions | Static import at top of file |
| **null ≠ undefined** | null and are different types | Match to interface: `T \null` → null, `T \undefined` → omit field |
| **@Entry build()** | Single root node required | Wrap in `Stack()` if you need conditional overlays |
| **getContext() deprecated** | Use `this.getUIContext().getHostContext()` | Cast: `as common.UIAbilityContext` |
| **router.pushUrl/back deprecated** | Use Navigation router instead | Or suppress warning (functional still works) |
| **arkts-no-standalone-this** | `this` in static methods not allowed | Use `ClassName.method()` |
| **arkts-no-aliases-by-index** | `Type['field']` not supported | Use literal type or omit |
| **Image empty URL crash** | `Image('')` causes runtime crash | Check `url.length > 0` before rendering |
| **Unicode smart quotes** | API data with U+2018/2019/201C/201D | Replace with ASCII equivalents before parse |
| **`for...of` / `.forEach()`** | All non-indexed loops fail at runtime | Use `for (let i = 0; i < arr.length; i++)` ONLY |
| **`get` accessor unreliable** | Getter + loop = empty page | Use `getXxx()` method instead of `get xxx()` |
| **`Map` type unreliable** | Map.forEach/get silently fail | Use array + manual lookup with indexed for loop |
