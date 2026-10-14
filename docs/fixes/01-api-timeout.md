# 01 · API 请求超时

**批次**：第一批 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

网络异常（弱网、代理挂起、服务端半开连接）时，部分接口的加载指示器会
无限转圈，既不报错也不超时退出，用户只能杀进程重启。

## 根因

`lib/core/api_client.dart` 使用 `http.Client` 发起请求，但**全文没有设置
任何超时**。`package:http` 的默认行为是无限等待：

- `ClientException` 只在**连接建立失败**时抛出，连接一旦建立但服务端不
  返回数据，就不会抛任何异常；
- 因此原有的 `_sendWithRetry` 重试逻辑在这种场景下**永远不会被触发**，
  请求 future 永远不完成。

## 改动内容

1. 新增 `import 'dart:async';`，新增常量：

   ```dart
   static const _requestTimeout = Duration(seconds: 15);
   ```

2. 请求统一包超时：`_client.get/post(...).timeout(_requestTimeout)`。

3. 新增 `on TimeoutException` 分支：与 `ClientException` 同样参与重试
   （指数退避 500ms / 1s）；重试耗尽后抛出可读的
   `ApiException('请求超时（>15s）')`，而不是把底层异常抛给 UI。

## 影响文件

- `lib/core/api_client.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 超时时间取 15s：大于正常公网请求耗时，又能让「无限等待」在可接受
  时间内变为明确错误。

## 回归风险与注意事项

- ⚠️ 依赖后端的慢接口（如歌词全文、云盘大列表）若本身偶发 >15s，
  现在会从「一直转圈」变成「15s 后报错 + 自动重试一次」。这是期望行为，
  但如果实际观察到某些接口频繁超时，应**按接口单独放宽**，而不是整体调大。
- 本次修复同时处理了 POST 的重试问题，见 `07-post-no-retry.md`。