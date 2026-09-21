import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/app_version.dart';
import '../models/music_models.dart';

/// 通过 GitHub Releases 检查并分发应用更新。
///
/// 更新仓库地址由 [AppConfig.updateRepoUrl] 决定：
/// - 版本号取 release 的 tag（如 `v3.2.0`）；
/// - 更新说明取 release body；
/// - 下载地址取 release 资产中的 .apk 文件（优先 arm64）；
/// - release body 中包含 `[force]` 标记时视为强制更新。
class AppUpdateService {
  AppUpdateService();

  static const String _updateRepo = AppConfig.updateRepoUrl;
  static const String _latestReleaseApi =
      'https://api.github.com/repos/$_updateRepo/releases/latest';

  static bool get isSupportedPlatform {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  Future<AppVersionInfo?> checkForUpdate() async {
    if (!isSupportedPlatform) {
      return null;
    }

    final version = await fetchLatestRelease();
    if (version == null || !version.isNewerThanCurrent) {
      return null;
    }
    return version;
  }

  /// 拉取最新 Release 并解析为 [AppVersionInfo]，无可用 .apk 资产时返回 null。
  Future<AppVersionInfo?> fetchLatestRelease() async {
    final uri = Uri.parse(_latestReleaseApi);
    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw StateError('检查更新失败（HTTP ${response.statusCode}）');
    }

    final json = asMap(jsonDecode(utf8.decode(response.bodyBytes)));
    final apkUrl = _pickApkAssetUrl(json['assets']);
    if (apkUrl == null) {
      return null;
    }

    final tag = asString(json['tag_name']) ?? '';
    final body = asString(json['body']) ?? '';

    return AppVersionInfo(
      platform: 'android',
      versionName: tag.startsWith('v') || tag.startsWith('V')
          ? tag.substring(1)
          : tag,
      versionCode: normalizedVersionCode(tag),
      updateContent: body,
      downloadUrl: apkUrl,
      forceUpdate: body.toLowerCase().contains('[force]'),
      releaseDate: DateTime.tryParse(asString(json['published_at']) ?? ''),
    );
  }

  /// 从 release 资产里挑 .apk：优先 arm64，其次名字里带 apk 的第一个。
  String? _pickApkAssetUrl(Object? assets) {
    final list = assets is List ? assets : const [];
    final apkAssets = <Map<String, dynamic>>[];
    for (final item in list) {
      final asset = asMap(item);
      final name = (asString(asset['name']) ?? '').toLowerCase();
      final url = asString(asset['browser_download_url']) ?? '';
      if (name.endsWith('.apk') && url.isNotEmpty) {
        apkAssets.add(asset);
      }
    }
    if (apkAssets.isEmpty) {
      return null;
    }
    for (final asset in apkAssets) {
      final name = (asString(asset['name']) ?? '').toLowerCase();
      if (name.contains('arm64')) {
        return asString(asset['browser_download_url']);
      }
    }
    return asString(apkAssets.first['browser_download_url']);
  }

  Future<void> downloadAndInstall(AppVersionInfo version) async {
    if (!version.hasDownloadUrl) {
      throw StateError('更新包下载地址为空');
    }

    final uri = Uri.tryParse(version.downloadUrl);
    if (uri == null) {
      throw StateError('更新包下载地址无效');
    }

    final success = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!success) {
      throw StateError('无法在浏览器中打开下载链接');
    }
  }
}
