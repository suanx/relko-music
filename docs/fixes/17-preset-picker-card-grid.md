# 17 · 预设音效选择器改为双列卡片

**批次**：音效 UI · **日期**：2026-10-14 · **状态**：已完成

## 问题现象

预设音效面板原来是**竖向列表**（每行一个 `ListTile` + 分割线）。加上
「浩渺声场」「悦耳人声」后预设已有 **15 个**，一屏放不下 7~8 个，需要
频繁上下滚动才能看完；且每个预设的**曲线形状不可见**，用户只能靠名字猜
（比如分不清「人声」和「悦耳人声」的差别）。

## 根因

这是列表布局的固有局限，不是数据问题。预设的**本质信息是那条 EQ 曲线**，
而列表把最该被看见的东西（曲线）完全隐藏了。

## 改动内容

`lib/ui/widgets/audio_effects_sheet.dart` 的 `_showPresetPicker`：

| 改动前 | 改动后 |
|--------|--------|
| `ListView.separated` 竖向 | `GridView.builder`，`crossAxisCount: 2`，两列并排 |
| 每行 `ListTile`（图标 + 名字 + 勾） | `_PresetCard`：卡片上半部是曲线缩略图，下半部是名字 |
| 不可见曲线 | 新增 `_PresetCurvePainter`，画出该预设的实际 EQ 曲线 |
| 勾选态是行尾小图标 | 选中卡片整块高亮（primaryContainer 底 + 2px primary 边框）+ 右上角圆形勾 |
| 底部弹层高度受限（默认 9/16 屏） | `isScrollControlled: true` + 高度上限 72% 屏，一屏能看到 4~6 张卡片 |
| 顶部无标题 | 加「音效预设」标题与预设总数 |

### 曲线缩略图的实现要点

- 复用主页面 `_EqualizerCurvePainter` 的**同一套坐标换算**
  （`_levelToY`：先按设备 EQ 区间归一化再翻转 y 轴），所以卡片预览
  与真实滑杆位置一致。
- 纵轴范围取 `player.equalizerConfig.minMillibels/maxMillibels`——
  **跟随设备实际区间**。很多机型只有 5 段且区间窄于 ±12dB，若硬编码
  ±12dB 会让所有卡片曲线看起来都很平，失去对比意义。
- 画基线（0dB）+ 半透明填充 + 2.2px 描边；未选中的卡片用
  `onSurface` 描边而不是 primary，避免一屏全是主色导致「都像选中」。
- 卡片文字 `maxLines: 1` + `ellipsis`，防止「3D环绕」这类名字换行
  撑破网格高度。

## 影响文件

- `lib/ui/widgets/audio_effects_sheet.dart`（`_showPresetPicker` 重写，
  新增 `_PresetCard`、`_PresetCurvePainter`）

## 验证方式

```bash
flutter analyze   # 4 条既有告警，零新增
flutter test      # 37 个全部通过
```

真机：Android → 自定义音效 → 均衡器 → 底部「预设」按钮，应看到两列
卡片网格，每张卡片上半部是对应曲线，选中项高亮。共 15 个预设。

## 回归风险与注意事项

1. **纯展示层改动**，未触碰 `PlayerController` 的任何状态与持久化逻辑，
   `applyEqualizerPreset` 的调用路径不变。
2. 网格高度依赖 `MediaQuery.sizeOf`，横屏/平板下 72% 上限仍可用；但
   `childAspectRatio: 0.86` 是固定值，若日后把卡片内容改高（比如加副
   标题）需要同步调这个值，否则会溢出。
3. 15 个预设 = 8 行，网格本身可滚动；底部弹层已改为
   `isScrollControlled`，不会出现「内容被裁掉却滚不动」。
4. 卡片曲线画的是**预设原始 10 段**，而设备可能只有 5 段——缩略图仅作
   形状示意，应用实际下发时仍由 `_levelsForBandCount` 重采样，行为不变。