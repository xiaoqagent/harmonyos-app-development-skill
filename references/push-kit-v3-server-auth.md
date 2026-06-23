# 华为 Push Kit V3 服务端鉴权 (REST API)

> 适用场景: 服务端通过 REST API 调用华为 Push Kit V3 向 HarmonyOS 5+ 设备推送消息。
> 踩坑日期: 2026-06-23 | 验证通过: ✅ 9设备推送成功

---

## 核心原则：HarmonyOS 5+ 必须用 JWT，OAuth2.0 已废弃

华为官方明确: **"HarmonyOS 5及以上系统版本推送不再支持Oauth2.0开放鉴权，请使用JWT（JSON Web Tokens）鉴权。"**

所有三种鉴权方式对比:

| 方式 | 结果 | 说明 |
|------|------|------|
| OAuth2.0 `client_credentials` (app_id + app_secret) | ❌ 80200001 | 仅支持旧版 HMS/Android |
| JWT → OAuth 交换 access_token → Push | ❌ 80200001 | access_token 无 Push Kit 权限 |
| **JWT 直连** (JWT 作为 Bearer token 直接调 Push API) | ✅ 80000000 | 正确方式 |

---

## JWT 生成流程

### 1. 获取服务账号密钥

从 AGC 控制台下载: 项目设置 → 服务账号密钥 → 创建/下载 JSON 文件。

文件格式 (`agc-apiclient-*.json` 或项目命名的 `*private.json`):
```json
{
    "project_id": "101653523864334050",
    "key_id": "4497dcbbd6404d5883da3c9fffb08e02",
    "private_key": "-----BEGIN PRIVATE KEY-----\nMIIJQw...\n-----END PRIVATE KEY-----\n",
    "sub_account": "118035699",
    "auth_uri": "https://oauth-login.cloud.huawei.com/oauth2/v3/authorize",
    "token_uri": "https://oauth-login.cloud.huawei.com/oauth2/v3/token"
}
```

### 2. 生成 RS256 JWT

```python
import json, time, base64
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend

def generate_push_jwt(key_path: str) -> str:
    """生成 Push Kit V3 鉴权 JWT"""
    key_data = json.loads(Path(key_path).read_text())
    
    # 加载私钥
    pkey = serialization.load_pem_private_key(
        key_data["private_key"].encode(), password=None, backend=default_backend()
    )
    
    def b64url(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()
    
    now = int(time.time())
    header = {"alg": "RS256", "kid": key_data["key_id"], "typ": "JWT"}
    payload = {
        "iss": key_data["sub_account"],
        "aud": "https://oauth-login.cloud.huawei.com/oauth2/v3/token",
        "iat": now,
        "exp": now + 3600,
    }
    
    header_b64 = b64url(json.dumps(header).encode())
    payload_b64 = b64url(json.dumps(payload).encode())
    signing_input = f"{header_b64}.{payload_b64}"
    
    signature = pkey.sign(
        signing_input.encode(), padding.PKCS1v15(), hashes.SHA256()
    )
    return f"{signing_input}.{b64url(signature)}"
```

### 3. 调用 Push API

```python
POST https://push-api.cloud.huawei.com/v3/{projectId}/messages:send
Authorization: Bearer <JWT>     # ← JWT 直接作为 Bearer token
Content-Type: application/json
push-type: 0                     # 0=通知消息
```

请求体:
```json
{
    "payload": {
        "notification": {
            "category": "IM",
            "title": "标题",
            "body": "内容",
            "clickAction": {"actionType": 0},
            "foregroundShow": true
        }
    },
    "target": {"token": ["设备push_token"]},
    "pushOptions": {
        "testMessage": true,
        "ttl": 86400
    }
}
```

---

## 错误码速查

| 错误码 | 含义 | 常见原因 |
|--------|------|----------|
| `80000000` | Success | 推送成功 |
| `80200001` | OAuth/JWT 认证错误 | ①用了 OAuth2.0 而非 JWT ②JWT→OAuth 换的 token 无 Push 权限 ③projectId 不匹配 |
| `80200003` | OAuth token 过期 | access_token 有效期 1h |
| `80300002` | AppPermission | URL 中 projectId 不对（常见: 错用了 app_id） |
| `80300007` | InvalidTokens | 设备 token 无效或格式错误 |

---

## URL 格式要点

- **正确**: `https://push-api.cloud.huawei.com/v3/{projectId}/messages:send`
- **错误**: `https://push-api.cloud.huawei.com/v3/{appId}/messages:send`（app_id ≠ projectId）

`projectId` 通常为数字串如 `101653523864334050`，在 AGC 控制台项目设置中可查。

---

## JWT 缓存策略

JWT 有效期 1 小时 (`exp = iat + 3600`)，建议缓存:

```python
_jwt_cache = {"token": "", "expires_at": 0}

def get_jwt():
    now = int(time.time())
    if _jwt_cache["token"] and _jwt_cache["expires_at"] > now + 60:
        return _jwt_cache["token"]
    jwt = generate_push_jwt(KEY_PATH)
    _jwt_cache["token"] = jwt
    _jwt_cache["expires_at"] = now + 3600
    return jwt
```

---

## 调试全流程复盘（从报错到打通）

真实踩坑顺序：

```
① 80300002 AppPermission
   根因: URL 用了 app_id(6917608171199263110) 而非 projectId(101653523864334050)
   修复: 改 URL → /v3/{PUSH_PROJECT_ID}/messages:send

② 80200001 OAuth/JWT 认证错误
   尝试1: OAuth2.0 client_credentials → ❌ (HarmonyOS 5+ 已废弃)
   尝试2: JWT → OAuth 交换 access_token → ❌ (access_token 无 Push Kit 权限)
   尝试3: JWT 直连 → ✅ 80000000
   根因: 华为官方明确"不再支持Oauth2.0开放鉴权，请使用JWT鉴权"

③ 通知栏收到，APP 对话列表无显示
   根因: 推送只走 Push Kit 到通知栏，未写入 offline_chats
   修复: 两层机制
   - 写入 offline_chats(__push_inbox__) → APP sync_pending 可拉取
   - WebSocket 连接时自动补推未读 push_messages(type: notification)
```

## APP 端对话列表显示方案

推送消息要进入 APP 对话列表，需要服务端两层保障：

### 1. offline_chats 写入（离线消息存储）

每次推送时，同时写入 `offline_chats` 表（session_id=`__push_inbox__`）：

```python
# server.py /api/push 中
db2 = sqlite3.connect(str(PUSH_DB))
existing = db2.execute(
    "SELECT content FROM offline_chats WHERE session_id = '__push_inbox__'"
).fetchone()
new_entry = f"[{title}]\n{text}\n---\n"
if existing:
    new_entry = existing[0] + "\n" + new_entry
db2.execute(
    "INSERT OR REPLACE INTO offline_chats (session_id, content) VALUES ('__push_inbox__', ?)",
    (new_entry,)
)
db2.commit()
```

APP 切后台重连时，发送 `sync_pending` 拉取 `__push_inbox__` 即可展示推送历史。

### 2. WebSocket 连接时增量补推

> ⚠️ 关键：用 `last_auto_push_id.txt` 记录上次推送的最大消息 ID，只推断开期间新增的消息，避免重复推送旧消息。

APP WebSocket 连接建立后，服务端只推送增量消息：

```python
# server.py websocket_push() 中，connected 之后
last_id_file = Path("~/.hermes/last_auto_push_id.txt")
last_id = int(last_id_file.read_text().strip()) if last_id_file.exists() else 0

unread = db.execute(
    "SELECT id, title, body, source, created_at FROM push_messages "
    "WHERE id > ? ORDER BY id ASC LIMIT 50",
    (last_id,)
).fetchall()

for row in unread:
    await websocket.send_json({
        "type": "notification",
        "id": row[0], "title": row[1], "body": row[2],
        "source": row[3], "created_at": row[4],
    })

if unread:
    last_id_file.write_text(str(unread[-1][0]))
```

APP 收到 `type: notification` 消息后在对话列表渲染为系统消息条目。

调试版 APP 获取的 token 以 `MASK` 开头。AGC 控制台手工推送（"测试消息"）支持 MASK token，但 REST API 的服务端推送对 MASK token 的支持有限。正式发布建议使用 MAAT（发布签名）token。
