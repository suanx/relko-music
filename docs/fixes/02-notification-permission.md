# 02 · Android 13+ 通知权限（POST_NOTIFICATIONS）

**批次**：第一批 · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

Android 13 及以上机型上，后台播放时通知栏不出现（或不显示播放控制按钮），
部分机型切后台回来后媒体通知被系统清掉。

## 根因

应用 `compileSdk` / `targetSdk` 跟随 Flutter（compileSdk = 37），已达到
Android 13（API 33）门槛。而 Android 13 起，**媒体通知需要运行时申请
`POST_NOTIFICATIONS` 权限**，否则系统会静默抑制通知。

项目此前的 `AndroidManifest.xml` 只声明了 `INTERNET`、`WAKE_LOCK`、
`MODIFY_AUDIO_SETTINGS` 等，**从未声明也从未申请过通知权限**。

## 改动内容

1. `android/app/src/main/AndroidManifest.xml` 增加声明：

   ```xml
   <!-- Android 13+（API 33）起媒体通知需要运行时声明该权限 -->
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
   ```

2. `lib/main.dart` 在 `runApp` 之后非阻塞申请（`permission_handler`
   本就在依赖中，此前仅 `download_service.dart` 用于存储权限）：

   ```dart
   if (Platform.isAndroid) {
     unawaited(Permission.notification.request()
         .catchError((_) => PermissionStatus.denied));
   }
   ```

## 影响文件

- `android/app/src/main/AndroidManifest.xml`
- `lib/main.dart`

## 验证方式

- `flutter analyze` 无新增问题。
- 手动验证需真机：Android 13+ 首次启动应弹出通知权限弹窗；
  拒绝后播放仍正常，仅通知栏不显示。

## 回归风险与注意事项

- 请求放在 `runApp` **之后**且用 `unawaited`，**不阻塞首帧**，启动速度不受影响。
- 用户拒绝后不再重复弹窗（系统行为），播放功能完全不受影响。
- 若后续要引导用户去系统设置开启，可在设置页加一个「通知权限」条目
  （`permission_handler` 提供 `openAppSettings()`），本轮未做。