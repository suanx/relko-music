import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/controllers/player_controller.dart';

void main() {
  group('均衡器预设列表', () {
    // 回归测试：新增预设（浩渺声场 / 悦耳人声）时容易犯的错——名字写重了
    // （UI 靠名字判断当前选中项，重名会导致打勾出现在两处）、
    // 段数不是 10（_levelsForBandCount 按下标重采样，段数不对会错位）、
    // 增益超出 ±12dB（写入系统 EQ 会被裁剪，回读后曲线与预设名不符）。
    test('所有预签名唯一', () {
      final names = PlayerController.equalizerPresets.map((p) => p.name).toList();
      expect(names.toSet().length, names.length, reason: '存在重名预设：$names');
    });

    test('每个预设都是 10 段', () {
      for (final preset in PlayerController.equalizerPresets) {
        expect(
          preset.levels.length,
          10,
          reason: '预设「${preset.name}」段数为 ${preset.levels.length}',
        );
      }
    });

    test('所有预设增益都在 ±12dB 内', () {
      for (final preset in PlayerController.equalizerPresets) {
        for (final level in preset.levels) {
          expect(
            level.abs(),
            lessThanOrEqualTo(1200),
            reason: '预设「${preset.name}」存在超范围增益 $level（${level / 100}dB）',
          );
        }
      }
    });

    test('新增的 DTS 风格预设已就位', () {
      final names = PlayerController.equalizerPresets.map((p) => p.name);
      expect(names, contains('浩渺声场'));
      expect(names, contains('悦耳人声'));
    });

    test('重置目标仍是第一个预设（平直）', () {
      expect(PlayerController.equalizerPresets.first.name, '平直');
    });
  });
}