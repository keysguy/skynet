# ROK 客户端网络层架构文档

**文档版本**: 1.0  
**最后更新**: 2026-02-26  
**范围**: 认证和网络连接层（EAuth1-3）

---

## 📋 目录

1. [网络层整体架构](#网络层整体架构)
2. [核心类关系](#核心类关系)
3. [调用流程顺序](#调用流程顺序)
4. [类详细说明](#类详细说明)
5. [数据流向](#数据流向)
6. [状态机流程](#状态机流程)

---

## 网络层整体架构

### 分层结构

```
┌─────────────────────────────────────────────────────────┐
│                  业务逻辑层 (Business)                   │
│  LoginMediator / LoginView / LoginCommand                │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│                   代理层 (Proxy)                         │
│  NetProxy (PureMVC Proxy Pattern)                       │
│  - SaveLoginInfo()                                      │
│  - Connection()                                         │
│  - SendSproto()                                         │
│  - OnAuthEvent() / OnNetEvent()                         │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│              应用层协议 (Application)                    │
│  SprotoSocketAp (Sproto Protocol Handler)              │
│  - setLoginInfo() - 设置登录参数                        │
│  - OnReciveEvent() - 接收和处理消息                     │
│  - SendHttpLine() - 发送认证包                          │
│  - SendSproto() - 发送游戏协议包                        │
│  - onAuth() - 认证状态转移                              │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│             网络客户端层 (Network Client)               │
│  INetClient / NetClient                                │
│  - Connect(host, port)                                 │
│  - Send(MemoryStream)                                  │
│  - Disconnect()                                        │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│           TCP 包装层 (TCP Wrapper)                      │
│  INetService / Skyunion.RunTime.NetService             │
│  - CreateClient()                                      │
│  NetworkNoneState / NetworkDisconnectedState           │
│  - Connect() / Disconnect()                            │
│  - ReceiveAsync() / SendAsync()                        │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│          TCP 会话层 (TCP Session)                       │
│  TCPSession (Raw Socket)                               │
│  - 处理基础 Socket 操作                                 │
│  - 包拆包                                                │
│  - OnReceive() / OnSend()                              │
└────────────────────────────┬────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────┐
│              传输层 (Transport)                          │
│  System.Net.Sockets.Socket                             │
│  - TCP 三次握手                                         │
│  - 数据包收发                                            │
└─────────────────────────────────────────────────────────┘
```

---

## 核心类关系

### 类依赖图

```
LoginMediator
    │
    ├─→ NetProxy (saved by AppFacade)
    │       │
    │       ├─→ SprotoSocketAp
    │       │       │
    │       │       ├─→ INetClient
    │       │       │       │
    │       │       │       ├─→ NetClient
    │       │       │       │       │
    │       │       │       │       └─→ INetService
    │       │       │       │               │
    │       │       │       │               └─→ NetworkManager
    │       │       │       │                   ├─→ INetworkState
    │       │       │       │                   │   ├─ NetworkNoneState
    │       │       │       │                   │   └─ NetworkDisconnectedState
    │       │       │       │                   │
    │       │       │       │                   └─→ TCPSession
    │       │       │       │                       │
    │       │       │       │                       └─→ Socket
    │       │       │       │
    │       │       │       └─→ Crypt (加密工具)
    │       │       │           ├─ randomkey()
    │       │       │           ├─ dhexchange()
    │       │       │           ├─ dhsecret()
    │       │       │           └─ hmac64()
    │       │       │
    │       │       └─→ SprotoRpc (协议转译)
    │       │           └─→ Protocol.Instance
    │       │
    │       └─→ OnAuthEvent() → AppFacade.SendNotification()
    │       └─→ OnNetEvent() → AppFacade.SendNotification()
    │
    └─→ AppFacade (消息总线)
        └─→ 其他 Mediator / Command
```

### 关键接口

```csharp
// 1. 网络客户端接口
public interface INetClient
{
    void Connect(string host, int port);
    void Send(MemoryStream stream);
    void Disconnect();
    void Reconnect();
}

// 2. 网络状态接口
public interface INetworkState
{
    void Connect(string host, int port, IProtocolResolver protocolResolver);
    void Disconnect();
    void Reconnect();
}

// 3. 协议解析接口
public interface IProtocolResolver
{
    NetPackInfo PacketProtocolResolve(ArraySegment<byte> segmentBytes);
}

// 4. 日志服务接口
public interface ILogService
{
    void Info(string message, Color color);
    void Error(string message);
}

// 5. 网络服务接口
public interface INetServcice
{
    INetClient CreateClient(
        Action<NetEvent, int> onNetEvent,
        Action<MemoryStream> onReceiveEvent,
        Func<ArraySegment<byte>, NetPackInfo> protocolResolver);
}
```

---

## 调用流程顺序

### 完整的登录连接流程

```
时间 →

[应用层登录]
1. LoginMediator.OnLogin()
   └─ 用户点击登录按钮，输入账号密码

2. LoginMediator.m_netProxy.SaveLoginInfo(
     serverIP, port, userName, password, serverNode)
   └─ NetProxy.SaveLoginInfo() @ L1350
   └─ 保存：m_userName, m_password, m_serverIP, m_serverPort, m_serverNode

3. LoginMediator 发送 CmdConstant.LoginToServer 通知
   └─ AppFacade.SendNotification(CmdConstant.LoginToServer)

[代理层处理]
4. 由 CmdConstant.LoginToServer 触发 → NetProxy.Connection() @ L1308
   └─ 读取保存的连接参数
   └─ SprotoSocketAp.CreateInstance(serverIP, serverPort, onNetEvent, onAuthEvent)

[Socket层初始化]
5. SprotoSocketAp.CreateInstance() @ L232
   └─ new SprotoSocketAp()
   └─ INetServcice.CreateClient() 创建网络客户端
   └─ 初始化 SprotoRpc 协议解析器
   └─ 保存 serverHost 和 serverPort

[应用层设置登录信息]
6. netClient.setLoginInfo(
     iggID, iggSdkToken, platform, language, clientIP, serverNode)
   └─ SprotoSocketAp.setLoginInfo() @ L254
   └─ 保存登录参数：iggID, iggSdkToken, platform, language, clientSdkIP, serverNode
   └─ 状态设置为 ELoginState.EAuth1
   └─ Task.Run(() => NetClient.Connect(serverHost, serverPort))

[TCP网络层连接]
7. NetClient.Connect(host, port) 
   └─ INetClient 实现类的方法
   └─ 调用底层 INetService.CreateClient() 建立的连接器

8. 连接建立后触发回调
   └─ OnNetEvent(NetEvent.ConnectComplete)
   └─ NetProxy.OnNetEvent() @ L275
   └─ AppFacade.SendNotification(CmdConstant.NetEvent, NetEvent.ConnectComplete)

[认证流程 - EAuth1状态]
9. 服务器发送 Challenge (随机8字节，Base64编码)
   └─ 触发 OnReciveEvent(packt)
   └─ packt 即为服务器发来的 Challenge

10. 进入 case ELoginState.EAuth1: @ L760
    └─ OnAuth(ELoginState.EAuth2) - 转移到 EAuth2 状态
    └─ challenge = Base64Decode(packt) - 解码 challenge
    └─ client_key = Crypt.randomkey() - 生成随机客户端密钥（8字节）
    └─ handshake = Crypt.dhexchange(client_key) - 计算 DH 交换值
    └─ handshake = Base64Encode(handshake) - Base64 编码
    └─ SendHttpLine(handshake) - 发送给服务器

[认证流程 - EAuth2状态]
11. 服务器发送自己的 DH 公钥
    └─ 触发 OnReciveEvent(packt) @ L760

12. 进入 case ELoginState.EAuth2: @ L781
    └─ OnAuth(ELoginState.EAuth3) - 转移到 EAuth3 状态
    └─ server_key = Base64Decode(packt) - 解码服务器 DH 公钥
    └─ des_key = Crypt.dhsecret(server_key, client_key) - 计算共享密钥
       └─ 此刻：client 和 server 都有相同的 des_key

13. 构造 Challenge 回应
    └─ challenge = HMAC64(challenge, des_key) - HMAC-64 计算
    └─ challenge = Base64Encode(challenge) - Base64 编码
    └─ SendHttpLine(challenge) - 发送到服务器

14. 构造登录凭证
    └─ strToken = "iggID:iggSdkToken:platform:language:clientIP:serverNode"
    └─ token = DES加密(strToken, des_key) - 使用共享密钥加密
    └─ token = Base64Encode(token) - Base64 编码
    └─ SendHttpLine(token) - 发送到服务器

[认证流程 - EAuth3状态]
15. 服务器返回认证结果
    └─ 触发 OnReciveEvent(packt)
    └─ 格式: "200 base64(uid@gameserver#subid ip@port)" 或错误码

16. 进入 case ELoginState.EAuth3: @ L805
    └─ 解析状态码 (200 成功, 400-408 错误)
    └─ 如果成功 (200):
       └─ ParseAuthResult(responseString) @ L869
       └─ 提取: uid, subid, gameserver, port, serverIP, serverName
       └─ OnAuth(ELoginState.ERedirectionGameServer) - 转移到重定向状态
       └─ SendNotification(CmdConstant.MaintainCheckSingleServer, serverName)

[游戏服务器重定向]
17. 连接游戏服务器 (ERedirectionGameServer 状态)
    └─ OnNetEvent(NetEvent.ConnectComplete) @ L283
    └─ 触发 SendRedirectionAuth() @ L295
    └─ 发送重定向认证令牌

18. 游戏服务器认证完成
    └─ case ELoginState.ERedirectionGameServer: @ L833
    └─ 验证返回码，转移到 EGameServerOK 状态
    └─ 此后所有通信都使用 Sproto 协议

[后续游戏消息通信]
19. ELoginState.EGameServerOK 状态
    └─ 所有普通游戏包通过 Sproto 协议传输
    └─ 使用 des_key 进行 DES 加密
    └─ 包头+游戏Session标识+压缩标识

20. SendSproto(SprotoTypeBase obj) @ L417
    └─ 序列化 Sproto 对象
    └─ DES 加密
    └─ 添加包头和 Session ID
    └─ NetClient.Send() 发出
```

---

## 类详细说明

### 1. LoginMediator (业务逻辑层)

**文件**: `Assets/Scripts/Hotfix/MVC/View_Mediator/Login/LoginMediator.cs`

**职责**:
- 管理登录UI界面交互
- 获取服务器列表
- 验证用户账号密码（本地HTTP验证，Editor模式）
- 调用 NetProxy 建立网络连接

**关键方法**:
```csharp
OnLogin()  // L285-292
  ├─ 验证账号密码格式
  ├─ 发送HTTP请求到 127.0.0.1:58110/api/login.php（仅Editor模式）
  └─ 调用 m_netProxy.SaveLoginInfo() 
     └─ AppFacade.SendNotification(CmdConstant.LoginToServer)
```

---

### 2. NetProxy (代理层 - PureMVC Proxy)

**文件**: `Assets/Scripts/Hotfix/MVC/Proxy/NetProxy.cs` (L1263-1382)

**职责**:
- 与视图层解耦，处理网络状态
- 保存登录信息
- 创建和管理 SprotoSocketAp 实例
- 转发网络事件到消息总线

**关键方法**:

| 方法 | 位置 | 功能 |
|------|------|------|
| `Connection()` | L1308 | 创建 SprotoSocketAp, 建立 TCP 连接 |
| `SaveLoginInfo()` | L1350 | 缓存登录参数 (IP, Port, 用户名等) |
| `OnAuthEvent()` | L1370 | 认证事件回调，发送状态通知 |
| `OnNetEvent()` | L1375 | 网络事件回调，发送网络状态通知 |
| `SendSproto()` | L1382 | 发送 Sproto 协议包 |

**内部属性**:
```csharp
public SprotoSocketAp netClient;           // Socket 应用层实例
private string m_userName;                 // 登录用户名
private string m_password;                 // 登录密码
private string m_serverIP;                 // 服务器IP
private int m_serverPort;                  // 服务器端口
private ELoginState m_CrrNetState;        // 当前认证状态
```

---

### 3. SprotoSocketAp (应用层协议处理)

**文件**: `Assets/Scripts/Hotfix/MVC/Proxy/NetProxy.cs` (L51-1130)

**职责**:
- 管理 DH 密钥交换
- 处理 EAuth 三步认证流程
- 加密/解密消息
- 序列化/反序列化 Sproto 协议

**认证状态机**:
```
EAuth1 ─(接收Challenge)─→ EAuth2
  ↓                         ↓
(生成DH密钥)          (交换DH密钥)
(发送DH公钥)          (计算des_key)
                      (发送Challenge+Token)
                          ↓
                      EAuth3 ─(验证成功)─→ ERedirectionGameServer
                          ↓                       ↓
                      (解析结果)            (连接游戏服务器)
                                                 ↓
                                          EGameServerOK
```

**关键方法**:

| 方法 | 位置 | 功能 |
|------|------|------|
| `CreateInstance()` | L232 | 工厂方法，创建 SprotoSocketAp 实例 |
| `setLoginInfo()` | L254 | 设置登录参数并启动连接 |
| `OnReciveEvent()` | L748 | 接收包的入口，按状态分发处理 |
| `OnAuth()` | L746 | 转移认证状态，触发回调 |
| `SendHttpLine()` | L407 | 发送认证阶段的包 (手动加\n结尾) |
| `SendSproto()` | L417 | 发送 Sproto 协议包 |
| `ParseAuthResult()` | L869 | 解析服务器返回的认证信息 |
| `SendRedirectionAuth()` | L295 | 重定向后的再次认证 |

**EAuth1 处理** (L760):
```csharp
case ELoginState.EAuth1:
  - 接收服务器 Challenge
  - 生成客户端 DH 密钥
  - 计算 DH 交换值
  - 发送 DH 公钥 (Base64+\n)
```

**EAuth2 处理** (L781):
```csharp
case ELoginState.EAuth2:
  - 接收服务器 DH 公钥
  - 计算共享密钥 des_key
  - 计算 Challenge HMAC
  - 发送 Challenge 回应 (Base64+\n)
  - 加密并发送 Token (DES加密+Base64+\n)
```

**EAuth3 处理** (L805):
```csharp
case ELoginState.EAuth3:
  - 接收认证结果 (状态码+Base64数据)
  - 解析响应数据
  - 提取 uid, subid, gameserver, port 等
  - 转移到 ERedirectionGameServer 状态
```

---

### 4. INetClient & NetClient (网络客户端)

**文件**:  
- 接口: `Assets/Skyunion/RunTime/NetService/NetClient.cs` (L20以上)
- 实现: 同文件 (L29-60)

**职责**:
- 提供 Socket 操作的统一接口
- 管理底层网络状态转移
- 调用具体的 TCP 包装层

**关键方法**:
```csharp
public void Connect(string host, int port)
  └─ 调用 mNetworkManager.Connect()
  
public void Send(MemoryStream stream)
  └─ 通过 mNetworkManager 发送数据
  
public void Disconnect()
  └─ 关闭连接
  
public void Reconnect()
  └─ 重新连接
```

---

### 5. INetService & PluginManager (网络服务工厂)

**文件**: `Assets/Skyunion/RunTime/NetService/` 目录

**职责**:
- 通过插件模式创建 NetClient 实例
- 依赖注入 Socket 回调处理函数

**使用方式**:
```csharp
INetServcice netService = PluginManager.Instance()
  .FindModule<INetServcice>();
  
sprotoSocketAp.NetClient = netService.CreateClient(
  sprotoSocketAp.OnNetEvent,        // 网络事件回调
  sprotoSocketAp.OnReciveEvent,     // 接收包回调
  sprotoSocketAp.PacketProtocolResolve);  // 协议解析
```

---

### 6. TCPSession (TCP 会话)

**文件**: `Assets/Skyunion/RunTime/NetService/TCPClient/TCPSession.cs`

**职责**:
- 基础 Socket 操作封装
- 实现包的收发
- 使用 SocketAsyncEventArgs 进行异步I/O

**关键方法**:
```csharp
ReceiveRequest()      // 异步接收请求
SendRequest()         // 异步发送请求
OnReceive()           // 接收完成回调
OnSend()              // 发送完成回调
OnDisconnect()        // 断开连接回调
```

---

### 7. 加密工具 - Crypt

**文件**: 未在代码中显示，为外部插件

**职责**:
- DH 密钥交换算法实现
- HMAC-64 计算
- DES 加密/解密

**API**:
```csharp
Crypt.randomkey()                    // 生成8字节随机密钥
Crypt.dhexchange(byte[] clientKey)  // 计算DH交换值
Crypt.dhsecret(server_key, client_key) // 计算共享密钥
Crypt.hmac64(byte[] challenge, byte[] key) // HMAC-64
CPatch.DesEncodeBuffer(des_key, data) // DES加密
CPatch.DesDecodeBuffer(des_key, data) // DES解密
```

---

### 8. SprotoRpc & Protocol (协议处理)

**文件**: `Sproto/` 目录（版本管理库）

**职责**:
- 序列化/反序列化 Sproto 消息格式
- 维护 RPC 会话 ID 映射
- Sproto 协议定义实现

**使用方式**:
```csharp
private SprotoRpc client;                              // RPC翻译器
private SprotoRpc.RpcRequest clientRequest;            // 请求构建器

client = new SprotoRpc(Protocol.Instance);
clientRequest = client.Attach(Protocol.Instance);

// 发送
byte[] buffer = clientRequest.Invoke(sprotoObj, session);

// 接收
SprotoRpc.RpcInfo info = client.Dispatch(receivedBuffer);
```

---

## 数据流向

### 登录凭证加密过程

```
明文:  iggID:password:platform:language:clientIP:serverNode
       │
       ├─ Step 1: 格式化为字符串
       │  "ID123456:abc123:3:1:192.168.1.100:game_server_001"
       │
       ├─ Step 2: 转换为字节数组 (UTF-8)
       │  [73, 68, 49, 50, 51, 52, 53, 54, ...]
       │
       ├─ Step 3: DES加密 (使用 des_key)
       │  des_key 来自 DH 密钥交换的结果
       │  加密后: [45, 87, 23, 156, 209, ...]
       │
       ├─ Step 4: Base64 编码 (安全传输)
       │  "LSvXG5zR0fGc..." 
       │
       └─ Step 5: 转为字节 + 换行符 + 通过 TCP 发送
          发送内容: "LSvXG5zR0fGc...\n"

⬇️ 网络传输 ⬇️

服务器端:
    ├─ 接收字节流
    ├─ 去除换行符
    ├─ Base64 解码
    ├─ DES 解密 (使用服务器的 des_key)
    └─ 得到明文: "ID123456:abc123:3:1:..."
```

### Challenge 验证过程

```
服务器生成:  challenge_A (8字节随机)
            │
            └─ Base64编码，通过TCP发送给客户端
                        │
客户端接收:  challenge_A (Base64)
            │
            ├─ Base64 解码
            │  challenge_bytes = [156, 45, 87, 23, ...]
            │
            ├─ 使用 des_key 计算 HMAC-64
            │  HMAC结果 = hash(challenge_bytes + des_key)
            │
            ├─ Base64 编码
            │  "VG5zR0fGc..." 
            │
            └─ 通过 TCP 发送给服务器
                        │
服务器验证:  接收 HMAC 值
            │
            ├─ 用自己的 des_key 计算期望的 HMAC
            │  expected_HMAC = hash(challenge_A + des_key)
            │
            ├─ 比对
            │  if (received_HMAC == expected_HMAC)
            │      ✓ DH 密钥交换成功，双方有相同的 des_key
            │  else
            │      ✗ 密钥不一致或数据被篡改，拒绝访问
            │
            └─ 继续后续认证或返回错误
```

---

## 状态机流程

### 认证状态完整流程图

```
┌─────────────┐
│  EAuth1     │  初始状态
└──────┬──────┘
       │ (服务器发送 Challenge)
       │ challenge = base64(8bytes_random)
       ▼
  保存 Challenge
  生成 client_key
  计算 DH 交换值
  
  发送: SendHttpLine(base64(DH_handshake))
       │
       │ (服务器发送 DH 公钥)
       │ server_key = base64(...)
       ▼
┌─────────────┐
│  EAuth2     │  状态转移
└──────┬──────┘
       │
       ├─ 接收 server_key, Base64解码
       ├─ 计算: des_key = DH_Secret(server_key, client_key)
       │
       ├─ 发送1: SendHttpLine(base64(HMAC64(challenge, des_key)))
       │
       ├─ 构造 Token: "iggID:token:platform:language:ip:serverNode"
       ├─ 加密: DES(token, des_key)
       │
       └─ 发送2: SendHttpLine(base64(encryptedToken))
          │
          │ (服务器处理:
          │   1. 验证 Challenge HMAC
          │   2. 解密并验证 Token
          │   3. 调用 auth_handler 
          │   4. 调用 login_handler
          │   5. 返回结果)
          ▼
┌─────────────┐
│  EAuth3     │  状态转移
└──────┬──────┘
       │
       ├─ 接收服务器响应: "200 base64(...)" 或 "400/401/403/..."
       │
       ├─ 成功 (200):
       │   ├─ 解析数据: uid@gameserver#subid ip@port
       │   ├─ 保存: uid, subid, serverHost, serverPort, serverIP, serverName
       │   │
       │   └─► 转移到 ERedirectionGameServer
       │
       └─ 失败 (400-408):
           └─► 转移到 EAuthError
               (报告错误，返回登录界面)

┌──────────────────────┐
│ ERedirectionGameServer│  重定向状态
└──────┬───────────────┘
       │
       ├─ NetClient.Connect(gameserver, port)
       │   (建立到游戏服务器的新TCP连接)
       │
       ├─ OnNetEvent(NetEvent.ConnectComplete)
       │
       ├─ SendRedirectionAuth() 发送重定向令牌
       │   认证串: base64(uid)@base64(servername)#base64(subid)
       │   + HMAC 校验
       │
       └─► 等待服务器回应
           │
           ▼
┌─────────────────────────┐
│  EGameServerOK          │  游戏服务器连接成功
│  (游戏运行状态)          │
└─────────────────────────┘
       │
       ├─ 此后所有通信使用 Sproto 协议
       ├─ 使用 des_key 进行 DES 加密
       ├─ Role_GetRoleList / Role_RoleLogin 等协议
       └─ 进入游戏主逻辑
```

---

## 错误状态处理

### AuthError 枚举

```csharp
public enum AuthError
{
    BadRequest = 400,        // Challenge HMAC 验证失败
    UnAuthorized = 401,      // auth_handler 返回失败（账号/密码错误）
    Forbidden = 403,         // login_handler 返回失败（权限不足/已登录）
    NotAccpetable = 406,     // 该用户已在线（禁止多登）
    UserBan = 407,          // 账号被封禁
    ToeknExpire = 408       // Token 已过期
}
```

### 错误流程

```
错误状态返回 (400/401/403/...)
    │
    ├─ OnAuth(ELoginState.EAuthError, errorCode)
    │
    ├─ AppFacade.SendNotification(CmdConstant.AuthEvent)
    │
    └─ UI 层监听通知，显示错误信息
       │
       ├─ 400: "服务器挑战失败，请重新连接"
       ├─ 401: "账号或密码错误"
       ├─ 403: "登录失败，账号可能被封禁"
       ├─ 406: "该账号已在线"
       ├─ 407: "账号被封禁，请联系客服"
       └─ 408: "登录凭证已过期，请重新登录"
```

---

## 关键设计模式

### 1. Factory Pattern（工厂模式）
```csharp
// 创建 Socket 应用层实例
SprotoSocketAp.CreateInstance(ip, port, connectEvent, authEvent)
```

### 2. Observer Pattern（观察者模式）
```csharp
// 网络事件回调
connectEvent += OnNetEvent
authEvent += OnAuthEvent
```

### 3. PureMVC Pattern（MVC 框架）
```csharp
// NetProxy 继承 GameProxy 实现数据隔离
public class NetProxy : GameProxy
{
    // 通过 AppFacade 发送通知给 Mediator/Command
}
```

### 4. State Machine（状态机）
```csharp
// ELoginState 枚举管理认证流程状态
enum ELoginState { EAuth1, EAuth2, EAuth3, ... }

// OnReciveEvent 中的 switch 实现状态转移
switch (_eLoginState)
{
    case ELoginState.EAuth1: ...
    case ELoginState.EAuth2: ...
    case ELoginState.EAuth3: ...
}
```

### 5. Asymmetric Cryptography（非对称加密）
```csharp
// DH 密钥交换实现端到端加密
des_key = Crypt.dhsecret(server_key, client_key)
```

---

## 消息通知流

### 通知类型 (CmdConstant)

| 通知 | 来源 | 监听者 |
|------|------|--------|
| `CmdConstant.LoginToServer` | LoginMediator | NetProxy |
| `CmdConstant.NetEvent` | SprotoSocketAp.OnNetEvent() | LoadingMediator |
| `CmdConstant.AuthEvent` | SprotoSocketAp.OnAuth() | LoadingMediator / GameEventGlobalMediator |
| `Role_GetRoleList.TagName` | 游戏服务器推送 | 多个 Mediator |
| `Role_RoleLogin.TagName` | 游戏服务器推送 | LoadingMediator |

### 通知链路

```
LoginMediator.OnLogin()
    │
    └─ AppFacade.SendNotification(CmdConstant.LoginToServer)
           │
           ├─ NetProxy.Connection()
           │     │
           │     ├─ SprotoSocketAp.setLoginInfo()
           │     │     │
           │     │     └─ NetClient.Connect()
           │     │
           │     └─ NetProxy.OnNetEvent() [回调]
           │           │
           │           └─ AppFacade.SendNotification(CmdConstant.NetEvent)
           │                   │
           │                   └─ LoadingMediator.HandleNotification()
           │
           └─ NetProxy.OnAuthEvent() [回调]
                 │
                 └─ AppFacade.SendNotification(CmdConstant.AuthEvent)
                         │
                         └─ LoadingMediator.HandleNotification()
```

---

## 性能优化与注意事项

### 1. 异步操作
```csharp
// 网络连接在后台线程运行
Task.Run(() => {
    NetClient.Connect(serverHost, serverPort);
});
```

### 2. 缓冲区重用
```csharp
// 使用 CircularBuffer 避免频繁分配内存
private CircularBuffer mReceiveBuffer;
private CircularBuffer mSendBuffer;
```

### 3. 异步 Socket I/O
```csharp
// 使用 SocketAsyncEventArgs 减少线程开销
SocketAsyncEventArgs mReceiveEventArgs;
SocketAsyncEventArgs mSendEventArgs;

bool pending = mSocket.ReceiveAsync(mReceiveEventArgs);
if (!pending) {
    // 同步完成
    OnReceive();
}
```

### 4. 会话映射追踪
```csharp
// 防止回包丢失或混乱
Dictionary<long?, int> m_dicSessionMapTag;   // Session → Tag 映射
Dictionary<long, int> m_dicTagMapGameSession;  // Tag → GameSession 映射
```

---

## 总结

ROK 客户端网络层采用**分层结构**：

1. **业务层** (LoginMediator) - UI 交互
2. **代理层** (NetProxy) - MVC 模式的数据代理
3. **应用层** (SprotoSocketAp) - EAuth 认证 + Sproto 协议
4. **网络层** (INetClient) - 单一职责的网络接口
5. **TCP 层** (TCPSession) - 基础 Socket 操作
6. **传输层** (System.Net.Sockets) - 原生 Socket

通过 **DH 密钥交换 + HMAC 验证 + DES 加密** 实现了：
- ✅ 端到端加密
- ✅ 防中间人攻击
- ✅ 防重放攻击
- ✅ 完整性检查

整个设计遵循**零信任原则**和**深度防御策略**。

