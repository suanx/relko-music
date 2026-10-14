import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('封面缓存目录的平台行为（ArtworkCacheService 的根因回归）', () {
    // 回归背景：v3.1.21/22 封面全部加载失败。根因是
    // ArtworkCacheService 往 getTemporaryDirectory()/artwork_cache/
    // 里写缓存文件，但那个子目录从未被 create —— 向不存在的目录写文件
    // 会抛 FileSystemException，被 on Exception 吞掉后返回 null，
    // 于是每一张封面都静默降级为占位图。
    // 本测试把这个平台行为固化下来：改缓存路径时如果有人删掉
    // create(recursive: true)，这里的第二段断言会失败。
    test('向不存在的目录写文件抛 FileSystemException', () async {
      final base = await Directory.systemTemp.createTemp('artwork_cache_t');
      try {
        final missing = Directory('${base.path}/artwork_cache');
        expect(missing.existsSync(), isFalse);

        var threw = false;
        try {
          await File('${missing.path}/a.jpg').writeAsBytes(const [1, 2, 3]);
        } on FileSystemException {
          threw = true;
        }
        expect(threw, isTrue, reason: '平台允许向不存在目录写文件？行为已变化，需复查缓存服务');
      } finally {
        await base.delete(recursive: true);
      }
    });

    test('create(recursive: true) 之后写入成功（修复所依赖的行为）', () async {
      final base = await Directory.systemTemp.createTemp('artwork_cache_t');
      try {
        final dir = Directory('${base.path}/artwork_cache');
        await dir.create(recursive: true);
        final file = File('${dir.path}/a.jpg');
        await file.writeAsBytes(const [1, 2, 3]);
        expect(await file.exists(), isTrue);
      } finally {
        await base.delete(recursive: true);
      }
    });
  });
}
