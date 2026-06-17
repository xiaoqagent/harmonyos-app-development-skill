# Chat消息持久化（Preferences + 防抖保存）

## 适用场景

聊天类APP需要保存历史消息，关闭APP后重新打开能恢复对话记录。

## 架构

```
每次消息变更 → scheduleSaveMessages() (500ms防抖) → saveMessages() → preferences.put(JSON)
启动时 → aboutToAppear() → loadMessages() → JSON.parse → messageList = restored
```

## 关键代码

### PreferencesHelper.ets（新增方法）

```typescript
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'xiaoq_preferences';
const KEY_MESSAGES: string = 'chat_messages';
const MAX_SAVED_MESSAGES: number = 200;

export interface StoredMessage {
  role: string;
  content: string;
}

export async function saveMessages(context: common.Context, messages: StoredMessage[]): Promise<void> {
  const toSave: StoredMessage[] = messages.slice(-MAX_SAVED_MESSAGES);
  const json: string = JSON.stringify(toSave);
  const pref: preferences.Preferences = await getPreferences(context);
  await pref.put(KEY_MESSAGES, json);
  await pref.flush();
}

export async function loadMessages(context: common.Context): Promise<StoredMessage[]> {
  const pref: preferences.Preferences = await getPreferences(context);
  const valueObj: preferences.ValueType = await pref.get(KEY_MESSAGES, '[]');
  const json: string = valueObj as string;
  return JSON.parse(json) as StoredMessage[];
}
```

### ChatPage.ets（防抖保存 + 启动恢复）

```typescript
// 1. 字段声明
private saveTimer: number | undefined = undefined;

// 2. 防抖保存方法
private scheduleSaveMessages(): void {
  if (this.saveTimer !== undefined) {
    clearTimeout(this.saveTimer);
  }
  this.saveTimer = setTimeout(() => {
    this.saveTimer = undefined;
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    saveMessages(ctx, this.messageList);
  }, 500);
}

// 3. 每次messageList.push后调用
this.messageList.push(newMsg);
this.scheduleSaveMessages();

// 4. 启动时恢复历史消息
aboutToAppear(): void {
  const ctx = this.getUIContext().getHostContext() as common.Context;
  loadMessages(ctx).then((saved: StoredMessage[]) => {
    if (saved.length > 0) {
      // 有历史记录则恢复
      const restored: ChatMessage[] = saved.map(m => ({ role: m.role, content: m.content }));
      this.messageList = restored;
    } else {
      // 首次使用显示欢迎
      this.messageList.push({ role: 'assistant', content: '你好！' });
    }
  });
}
```

## 注意

- 用`slice(-200)`限制最大200条，避免Preferences存储过大
- 防抖500ms避免频繁写磁盘（单次对话可能连续收到多条消息）
- 启动时用`loadMessages`替换默认欢迎消息——有历史则恢复，无历史才显示欢迎语
- Preferences存储的ValueType只能存string/number/boolean，消息列表需要JSON.stringify
