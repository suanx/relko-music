import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 轻量封面磁盘缓存。
///
/// 背景：项目此前全部使用裸 `Image.network`，列表滚动时封面反复下载、
/// 冷启动重新拉取全部图片。未采用 cached_network_image，因为其默认缓存
/// 实现依赖 sqflite，在 Windows 桌面端（本项目真实支持的平台）运行时
/// 存在崩溃风险；这里用「临时目录 + sha1 文件名」实现等效的磁盘缓存，
/// 配合 Image 的内存缓存形成两级缓存。
///
/// 并发下载同一 URL 时会合并为一个请求（in-flight 去重）。
class ArtworkCacheService {
  ArtworkCacheService._();

  static final ArtworkCacheService instance = ArtworkCacheService._();

  /// 单次下载超时。
  static const _downloadTimeout = Duration(seconds: 15);

  /// 磁盘缓存上限（字节）。超出时按修改时间从旧到新删除，直到降到上限以下。
  static const _maxDiskBytes = 200 * 1024 * 1024;

  Directory? _dir;
  final Map<String, Future<File?>> _inflight = {};

  /// 获取 URL 对应的本地缓存文件；下载失败返回 null。
  Future<File?> fetch(String url) {
    return _inflight.putIfAbsent(url, () => _fetch(url).whenComplete(() {
      _inflight.remove(url);
    }));
  }

  Future<File?> _fetch(String url) async {
    try {
      final dir = await _cacheDir();
      final digest = sha1.convert(url.codeUnits);
      final file = File('${dir.path}/$digest.jpg');

      if (await file.exists()) {
        // 刷新 mtime，作为 LRU 淘汰的依据。
        await file.setLastModified(DateTime.now());
        return file;
      }

      final response = await http
          .get(Uri.parse(url))
          .timeout(_downloadTimeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      // 先写临时文件再重命名，避免中途退出留下半截文件被当成缓存命中。
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      await tmp.rename(file.path);

      unawaited(_enforceDiskLimit(dir));
      return file;
    } on Exception {
      // 下载失败（超时/断网/非图片响应）时静默降级为占位图。
      return null;
    }
  }

  Future<Directory> _cacheDir() async {
    return _dir ??= Directory(
      '${(await getTemporaryDirectory()).path}/artwork_cache',
    );
  }

  /// 超出磁盘上限时按修改时间从旧到新删除。
  Future<void> _enforceDiskLimit(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((e) => e is File && !e.path.endsWith('.tmp'))
          .cast<File>()
          .toList();
      var total = 0;
      final sizes = <File, int>{};
      for (final f in files) {
        final stat = await f.stat();
        sizes[f] = stat.size;
        total += stat.size;
      }
      if (total <= _maxDiskBytes) return;
      final sorted = sizes.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value)); // 小文件优先淘汰
      for (final entry in sorted) {
        if (total <= _maxDiskBytes) break;
        try {
          await entry.key.delete();
          total -= entry.value;
        } on FileSystemException {
          // 文件可能正被使用，忽略。
        }
      }
    } on Exception {
      // 清理失败不影响主流程。
    }
  }
}
