# 07 · 非幂等 POST 不再自动重试

**批次**：第二批 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

用户点击「添加歌曲到歌单」偶尔出现**重复添加**；点「获取验证码」偶尔
收到两条短信。

## 根因

`lib/core/api_client.dart` 的 `_sendWithRetry()` 对**所有请求**（含 POST）
在遇到 5xx 或连接异常时自动重试（最多 2 次）。但项目中的 POST 大多是
**非幂等操作**：

- `/playlist/tracks/add`（加歌到歌单）
- `/captcha/sent`（发送短信验证码）
- `/login/cellphone`（手机号登录）

连接异常时服务端**可能已处理成功**（响应回不来），重试就会造成重复提交。

## 改动内容

给 `_sendWithRetry()` 增加 `allowRetry` 参数，`post()` 显式传 `false`：

```dart
Future<dynamic> post(String path, {...}) {
  return _sendWithRetry(
    () => _client.post(...),
    // POST 多为非幂等操作，失败重试可能造成重复提交
    allowRetry: false,
  );
}
```

实现上 `final attempts = allowRetry ? maxRetries : 0;`，即一次都不重试，
错误直接抛给调用方。GET / getRaw 行为不变（仍重试）。

## 影响文件

- `lib/core/api_client.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 手动验证：模拟弱网下加歌/收验证码，确认不再出现重复。

## 回归风险与注意事项

- ⚠️ **部分调用方可能依赖了 POST 的重试**：此前 5xx 时 POST 会自动重试
  2 次并大概率成功，现在不会了。若某个接口实测 5xx 率偏高导致用户体感
  变差，应在该**具体调用点**自行加重试，而不是恢复全局重试。
- 幂等的查询型 POST（如某些 `/user/vip/detail`）现在也不会重试了。
  如需恢复，可在对应调用点改用 `get` 或加显式重试包装。