# XiaoQ API 文件浏览端点

xiaqo-api（FastAPI 服务，默认端口 8089）提供文件浏览和 Token 统计两个核心功能组。本文档聚焦文件浏览相关端点。

## 基础信息

- **base URL（公网）**：`https://xiaoq.xiao-q.com`
- **base URL（局域网）**：`http://<Windows主机IP>:8089`
- **鉴权**：`Authorization: Bearer <API_SERVER_KEY>`
- **内容类型**：`application/json`
- **服务绑定**：WSL 内 `0.0.0.0:8089`（WSL2镜像网络模式下局域网直接可达，无需portproxy）
- **服务文件**：`~/workspace/xiaoq-api/server.py`

## 端点

### GET /api/files

列出 Obsidian Vault 目录内容。

**参数**：`path`（可选，Vault 内相对路径，空=根目录）

**返回示例**：
```json
{
  "path": "",
  "items": [
    {"type": "directory", "name": "00-Inbox", "path": "00-Inbox"},
    {"type": "directory", "name": "02-Research", "path": "02-Research"},
    {"type": "file", "name": "index.md", "path": "index.md"}
  ]
}
```

**限制**：仅返回 Vault 根目录下的直接子项，不递归。

### GET /api/files/read

读取文件内容。

**参数**：`path`（必填，文件相对路径）

**返回示例**：
```json
{
  "content": "# 文件内容\n\n这是 markdown 文本...",
  "path": "02-Research/some-report.md"
}
```

**限制**：仅支持文本类文件（.md/.txt/.json/.yaml/.py/.html/.css）。不支持二进制文件。

### GET /api/files/search

搜索 .md 文件名。

**参数**：`q`（必填，搜索关键词，最少1字符）

**返回**：匹配的文件路径列表，最多50条。

## ArkTS 调用示例

```typescript
import { rcp } from '@kit.RemoteCommunicationKit';

const headers: Record<string, string> = {
  'Authorization': 'Bearer ' + apiKey
};

// 列出目录
const listReq: rcp.Request = new rcp.Request(
  '/api/files?path=' + encodeURIComponent(dirPath), 'GET', headers, {});
const listRes: rcp.Response = await session.fetch(listReq);
const data = listRes.toJSON() as Record<string, Object>;

// 读取文件
const readReq: rcp.Request = new rcp.Request(
  '/api/files/read?path=' + encodeURIComponent(filePath), 'GET', headers, {});
const readRes: rcp.Response = await session.fetch(readReq);
const content = (readRes.toJSON() as Record<string, Object>)['content'] as string;
```

## 注意事项

- 文件端点现在走 WiFi 自动切换（需每个页面独立实现 detectApiUrl()），详见 SKILL.md 中「⚠️ 常见陷阱：所有发起网络请求的页面必须一致检测SSID」
- xiaoq-api 绑定 `0.0.0.0:8089`，在WSL2镜像网络模式下，局域网内直接访问 `http://192.168.3.87:8089` 即可
- `encodeURIComponent()` 确保中文路径和特殊字符正确编码
- 完整 FileApi 封装类见 `templates/harmonyos-next-file-browser/FileApi.ets`
