# WiFi 文件打开失败排查链（v1.3.0 实战）

## 症状

APP 文件浏览页签（FilesPage）在 WiFi 下能显示文件列表，但点开文件后 FileViewPage 一直转圈。切 5G 正常。

## 排查层次

### 第1层：代码检查（FileViewPage.ets）

**发现问题**：FileViewPage 硬编码了 `PUBLIC_API`（公网地址），没有做 WiFi SSID 检测。而 FilesPage 有 `detectFilesApiUrl()` 检测。

**代码差异**：
```typescript
// FilesPage ✅ — 有 WiFi 检测
this.detectFilesApiUrl().then((apiUrl: string) => { ... });

// FileViewPage ❌ — 硬编码公网
const apiUrl: string = PUBLIC_API;
```

**根因①**：Home WiFi 路由器不支持 NAT hairpin（内网设备访问自己的公网 IP）。FilesPage 走局域网 `192.168.3.87:8089` 正常，FileViewPage 走公网 `xiaoq.xiao-q.com` 因 hairpin 问题超时。

**修复**：给 FileViewPage 添加同样的 `detectApiUrl()` 方法，检测 WiFi SSID 并切换到局域网 URL。

### 第2层：编译验证 + 版本号核对

- 改完代码后版本号从 v1.2.0 → v1.3.0
- 用户用 DevEco Studio 重新编译安装

### 第3层：网络连通性验证

测试命令：
```bash
# 本地（WSL 内）
curl --noproxy '*' http://127.0.0.1:8089/health         # ✅ 200

# WSL 内部 IP
curl --noproxy '*' http://172.27.104.190:8089/health     # ✅ 200

# Windows IP（通过 portproxy，实际网络路径）
curl --noproxy '*' http://192.168.3.87:8089/health       # ❌ timeout
```

对比端口：
```bash
curl --noproxy '*' http://192.168.3.87:8642    # ✅ 401 (fast)
curl --noproxy '*' http://192.168.3.87:8787    # ✅ 302 (fast)
curl --noproxy '*' http://192.168.3.87:8089    # ❌ timeout
```

### 第4层：portproxy 和防火墙检查

- `netsh interface portproxy show all` → 规则已存在（192.168.3.87:8089 → 127.0.0.1:8089）
- 添加防火墙规则 → 仍超时

### 第5层：Windows 端口排除范围

**根因②**：Windows 保留端口范围 `8055-8154`，8089 在此范围内。

```powershell
netsh interface ipv4 show excludedportrange protocol=tcp
# → 8055 ~ 8154 ← 8089 在此范围，portproxy 无声失效
```

Hyper-V/WSL 安装后内核级保留此范围，portproxy 规则虽显示在列表中但永不生效。

## 修复总结

| 改动 | 内容 |
|------|------|
| 代码 | FileViewPage.ets 添加 `detectApiUrl()` WiFi SSID 检测 |
| 端口 | xiaoq-api 从 8089 → **8866**（不在保留范围内）|
| Service | `~/.config/systemd/user/xiaoq-api.service` 改 PORT=8866 |
| Portproxy | 删 8089 规则，加 8866 规则 |
| 防火墙 | 放行 8866 |
| 验证 | `curl http://192.168.3.87:8866/health` → **200 (5ms)** ✅ |

## 教训

1. **所有发起 HTTP 请求的页面都必须独立检测 WiFi**，不要假设一个页面检测够了
2. **portproxy 规则存在 ≠ 规则生效**——必须测通再从代码层面排查
3. **Windows 端口排除范围**是无声杀手——`netsh portproxy add` 不报错，`show all` 看得见，就是不通
4. 选端口时先 `netsh interface ipv4 show excludedportrange` 确认可用
