# PreferencesHelper — 可靠的数据持久化

替代 `PersistentStorage.persistProp`（后者在APP重启后可能丢失数据）。

## 完整实现

```typescript
// entry/src/main/ets/utils/PreferencesHelper.ets
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'xiaoq_preferences';
const KEY_API_KEY: string = 'api_key';

let preferencesInstance: preferences.Preferences | null = null;

async function getPreferences(context: common.Context): Promise<preferences.Preferences> {
  if (preferencesInstance !== null) {
    return preferencesInstance;
  }
  preferencesInstance = await preferences.getPreferences(context, STORE_NAME);
  return preferencesInstance;
}

export async function saveApiKey(context: common.Context, apiKey: string): Promise<void> {
  const pref = await getPreferences(context);
  await pref.put(KEY_API_KEY, apiKey);
  await pref.flush();
}

export async function loadApiKey(context: common.Context): Promise<string> {
  const pref = await getPreferences(context);
  const valueObj: preferences.ValueType = await pref.get(KEY_API_KEY, '');
  const value: string = valueObj as string;
  return value;
}
```

## 使用方式

**ChatPage.ets** — 保存时写入：
```typescript
import { common } from '@kit.AbilityKit';
import { saveApiKey, loadApiKey } from '../utils/PreferencesHelper.ets';

private async saveSettings(): Promise<void> {
  this.apiKey = this.tempApiKey;
  const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
  await saveApiKey(ctx, this.apiKey);
  // ...
}
```

**ChatPage.ets** — 启动时加载：
```typescript
aboutToAppear(): void {
  const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
  loadApiKey(ctx).then((savedKey: string) => {
    if (savedKey !== '') {
      this.apiKey = savedKey;    // @StorageLink 自动同步到所有页面
    }
    this.tempApiKey = this.apiKey;
    // 继续初始化...
  });
}
```

## 关键点

- `pref.get()` 返回 `ValueType`（string|number|boolean 联合类型），必须 `as string` 才能过 ArkTS 严格模式
- `preferencesInstance` 用模块级变量缓存，避免多次打开同个存储文件
- Preferences 文件存储在 APP 内部数据目录，用户不可见
- `@StorageLink` 负责运行时跨页面同步，Preferences 负责磁盘持久化，两者互补
