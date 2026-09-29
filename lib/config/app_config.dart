import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  const AppConfig._();

  static const appName = 'REIKO';

  /// 兜底版本号：仅在 PackageInfo 读取失败时使用。
  /// 正常情况下以 pubspec.yaml 的 version 为唯一数据源，发布时无需改这里。
  static const _fallbackVersion = '3.1.0';

  /// 应用版本号与版本码（启动时从 PackageInfo 加载，见 [loadAppVersion]）。
  /// 版本码优先取 CI 通过 --build-number 注入的 buildNumber（随每次构建
  /// 单调递增）；本地构建无 buildNumber 时回退为版本号去点后的数字串
  /// （如 3.1.1 -> 311），供检查更新比较。
  static String appVersion = _fallbackVersion;
  static String appVersionCode = _fallbackVersion;

  /// 从系统 PackageInfo 加载真实版本号（来自 pubspec.yaml 的 version）。
  /// 必须在 main() 中于 runApp 之前 await 调用，保证检查更新拿到正确版本。
  static Future<void> loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.trim().isNotEmpty) {
        appVersion = info.version.trim();
        appVersionCode = info.version.trim();
      }
      // CI 构建注入的 buildNumber（= R2 清单的 versionCode，随每次构建
      // 单调递增）。存在且合法时优先使用，避免「版本号去点拼接」在
      // patch 位进位（3.1.9 -> 3.1.10，319 vs 3110）时的比较歧义。
      final buildNumber = int.tryParse(info.buildNumber);
      if (buildNumber != null && buildNumber > 0) {
        appVersionCode = '$buildNumber';
      }
    } catch (_) {
      // 读取失败时保留兜底常量，不影响应用启动。
    }
  }

  static const _defaultApiBaseUrl = 'https://music.api.hoilai.cn';
  static const _customBaseUrlKey = 'settings.custom_api_base_url';

  /// 应用更新仓库：检查更新/下载安装包均来自该仓库的 GitHub Releases。
  static const updateRepoUrl = 'suanx/relko-music';

  /// 应用更新清单地址（R2 公开访问的 latest.json）。
  /// 检查更新优先读取该清单，失败时回退到 [updateRepoUrl] 的 GitHub Releases。
  /// CI 构建时会通过 --dart-define 覆盖此默认值，本地构建直接使用默认值。
  static const updateManifestUrl = String.fromEnvironment(
    'KA_MUSIC_UPDATE_MANIFEST_URL',
    defaultValue: 'https://pub-ecb9535c425f480285e165bffc5754c7.r2.dev/latest.json',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'KA_MUSIC_API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  );

  static const debugLyrics = bool.fromEnvironment(
    'KA_MUSIC_DEBUG_LYRICS',
    defaultValue: true,
  );

  // ===== 缓存与下载配置 =====
  /// 数据缓存目录名 / 下载目录名 / 播放缓存目录名
  static const cacheDirName = 'ka_music_cache';
  static const downloadDirName = 'REIKO';
  static const playCacheDirName = 'ka_music_play_cache';

  /// 数据缓存 TTL（分级）
  static const homeCacheTtl = Duration(minutes: 30); // 首页推荐
  static const playlistDetailTtl = Duration(hours: 24); // 歌单/专辑详情
  static const userProfileTtl = Duration(hours: 24); // 用户信息+歌单列表

  /// 播放缓存大小上限（超过则按 LRU 清理），下载不设上限（用户主动管理）
  static const playCacheMaxBytes = 300 * 1024 * 1024; // 300MB

  /// 下载并发数
  static const maxConcurrentDownloads = 3;

  /// User-configured API base URL override. When non-null, takes precedence
  /// over the compile-time `apiBaseUrl`.
  static String? _customBaseUrl;

  /// The effective API base URL (custom if set, otherwise the default).
  static String get effectiveBaseUrl => _customBaseUrl ?? apiBaseUrl;

  /// Whether the user has set a custom API base URL.
  static bool get hasCustomBaseUrl => _customBaseUrl != null;

  /// The custom API base URL, or null if using the default.
  static String? get customBaseUrl => _customBaseUrl;

  /// The default (built-in) API base URL.
  static String get defaultApiBaseUrl => apiBaseUrl;

  /// Load the custom API base URL from persistent storage.
  static Future<void> loadCustomBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_customBaseUrlKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _customBaseUrl = stored.trim();
    }
  }

  /// Save a custom API base URL. Pass `null` or empty to reset to default.
  static Future<void> saveCustomBaseUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == apiBaseUrl) {
      _customBaseUrl = null;
      await prefs.remove(_customBaseUrlKey);
    } else {
      _customBaseUrl = trimmed;
      await prefs.setString(_customBaseUrlKey, trimmed);
    }
  }

  static Uri apiUri(String path, [Map<String, Object?> query = const {}]) {
    final base = Uri.parse(effectiveBaseUrl);
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final normalizedBasePath = base.path.endsWith('/')
        ? base.path
        : '${base.path}/';

    return base.replace(
      path: '$normalizedBasePath$cleanPath',
      queryParameters: {
        for (final entry in query.entries)
          if (entry.value != null && entry.value.toString().isNotEmpty)
            entry.key: entry.value.toString(),
      },
    );
  }
}
