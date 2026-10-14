import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/models/music_models.dart';

void main() {
  group('Song.toCache/fromCache 的 source 字段', () {
    // 回归测试：网易云歌曲（source=netease）经缓存序列化回读后，
    // 必须仍是 netease，否则播放会走酷狗分支请求 hash 而失败。
    test('网易云歌曲缓存回读后 source 保持 netease', () {
      final song = Song(
        id: '1234567',
        title: '测试歌曲',
        artist: '测试歌手',
        hash: 'ne_1234567',
        source: SongSource.netease,
      );

      final restored = Song.fromCache(song.toCache());

      expect(restored.source, SongSource.netease);
    });

    test('本地音乐缓存回读后 source 保持 local', () {
      final song = Song(
        id: '/storage/emulated/0/Music/test.mp3',
        title: '本地歌曲',
        artist: '本地歌手',
        hash: 'local_hash',
        source: SongSource.local,
      );

      final restored = Song.fromCache(song.toCache());

      expect(restored.source, SongSource.local);
    });

    test('酷狗歌曲缓存回读后 source 仍为 kugou（默认值）', () {
      final song = Song(
        id: '888',
        title: '酷狗歌曲',
        artist: '歌手',
        hash: 'HASH888',
      );

      expect(song.toCache().containsKey('source'), isFalse);

      final restored = Song.fromCache(song.toCache());
      expect(restored.source, SongSource.kugou);
    });

    test('未知 source 字符串安全回退为 kugou（旧缓存兼容）', () {
      final cache = Song(
        id: '1',
        title: '歌曲',
        artist: '歌手',
        hash: 'H1',
      ).toCache();
      cache['source'] = 'some_unknown_source';

      final restored = Song.fromCache(cache);

      expect(restored.source, SongSource.kugou);
    });

    test('云盘标记与其它字段一并正确回读', () {
      final song = Song(
        id: 'c1',
        title: '云盘歌曲',
        artist: '歌手',
        hash: 'HC1',
        isCloudDrive: true,
      );

      final restored = Song.fromCache(song.toCache());

      expect(restored.isCloudDrive, isTrue);
      expect(restored.title, '云盘歌曲');
      expect(restored.hash, 'HC1');
    });
  });
}