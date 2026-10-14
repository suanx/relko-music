import 'dart:async';
import 'dart:convert';
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
      // 之前用 url.codeUnits 做哈希：code unit 可大于 255，超出字节范围，
      // 对非 ASCII URL 会产生歧义哈希；utf8 字节才是规范的哈希输入。
      final digest = sha1.convert(utf8.encode(url));
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
    } catch (_) {
      // 下载/写盘失败（超时、断网、目录不可写等）时静默降级为占位图。
      // 注意用 catch(_) 而不是 on Exception：插件缺失这类 Error 不继承
      // Exception，漏掉会让调用方的 Future 永远挂起、封面停在骨架屏。
      return null;
    }
  }

  Future<Directory> _cacheDir() async {
    return _dir ??= await _ensureCacheDir();
  }

  /// 子目录必须显式创建：getTemporaryDirectory() 只保证 cache/ 存在，
  /// 直接往不存在的 artwork_cache/ 里写文件会抛 FileSystemException。
  /// 这是 v3.1.21/22 全部封面加载失败的根因。
  Future<Directory> _ensureCacheDir() async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/artwork_cache',
    );
    await dir.create(recursive: true);
    return dir;
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
        ..sort((a, b) => a.key.lastModifiedSync().compareTo(b.key.lastModifiedSync()));
      for (final entry in sorted) { // 最旧的先淘汰（LRU）
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
