import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    this.url,
    required this.size,
    this.borderRadius = 8,
  });

  final String? url;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    final child = imageUrl == null
        ? _Fallback(size: size)
        : imageUrl.startsWith('content://')
            ? _ContentUriImage(
                uri: imageUrl,
                size: size,
                borderRadius: borderRadius,
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _Fallback(size: size),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) {
                    return child;
                  }
                  return _ShimmerBox(
                    size: size,
                    borderRadius: borderRadius,
                  );
                },
              );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: size.isFinite
          ? SizedBox.square(dimension: size, child: child)
          : SizedBox.expand(child: child),
    );
  }
}

/// 加载 content:// URI 的图片（用于本地音乐专辑封面）。
class _ContentUriImage extends StatefulWidget {
  const _ContentUriImage({
    required this.uri,
    required this.size,
    required this.borderRadius,
  });

  final String uri;
  final double size;
  final double borderRadius;

  @override
  State<_ContentUriImage> createState() => _ContentUriImageState();
}

class _ContentUriImageState extends State<_ContentUriImage> {
  static const _channel = MethodChannel('kgka_music_hl/local_music');
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _ContentUriImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 列表刷新/重排时同一位置会复用 State，uri 变化需要重新加载封面，
    // 否则会显示上一次的旧封面（封面错位）。
    if (oldWidget.uri != widget.uri) {
      _bytes = null;
      _loading = true;
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    // 记录发起加载时的 uri，用于丢弃过期结果，避免快速刷新时的竞态。
    final uri = widget.uri;
    try {
      // 从 content URI 中提取 albumId
      final albumId = int.tryParse(uri.split('/').last);
      if (albumId == null || albumId <= 0) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final bytes = await _channel.invokeMethod<Uint8List>(
        'getAlbumArt',
        {'albumId': albumId},
      );
      if (!mounted || widget.uri != uri) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _ShimmerBox(size: widget.size, borderRadius: widget.borderRadius);
    }
    if (_bytes == null) {
      return _Fallback(size: widget.size);
    }
    return Image.memory(_bytes!, fit: BoxFit.cover);
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size});

  /// 容器边长；无限大（整页填充）时按固定尺寸渲染。
  final double size;

  /// 无封面歌曲的默认占位图（App 吉祥物，带透明背景）。
  static const _defaultCoverAsset = 'lib/assets/default_cover.png';

  @override
  Widget build(BuildContext context) {
    // 吉祥物统一占背景边长的 70%；全幅场景（size 无限大）用 LayoutBuilder
    // 拿真实约束尺寸计算，所有调用点（播放页、专辑网格等）自动适配。
    Widget buildBody(double imageExtent) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFE9A8),
              Color(0xFFFFF6DC),
              Color(0xFFBFE0FA),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 暖黄与浅蓝弥散光斑，整体高斯模糊 60 营造朦胧眩晕感
            const _GlassSheen(),
            Center(
              child: Image.asset(
                _defaultCoverAsset,
                width: imageExtent,
                height: imageExtent,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ],
        ),
      );
    }

    if (size.isFinite) {
      return buildBody((size * 0.70).clamp(28.0, 600.0));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return buildBody((side * 0.70).clamp(96.0, 600.0));
      },
    );
  }
}

/// 背景弥散光斑层：暖黄与浅蓝交错光晕，整体高斯模糊（sigma 60），
/// 形成柔和的朦胧眩晕感。纯装饰性叠层，不参与命中测试。
class _GlassSheen extends StatelessWidget {
  const _GlassSheen();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: const Stack(
          fit: StackFit.expand,
          children: [
            // 左上暖黄光晕
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.55, -0.6),
                  radius: 0.9,
                  colors: [Color(0xC8FFD166), Color(0x00FFD166)],
                ),
              ),
            ),
            // 右下浅蓝光晕
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.65, 0.7),
                  radius: 1.0,
                  colors: [Color(0xC88FCBFF), Color(0x008FCBFF)],
                ),
              ),
            ),
            // 中部穿插的浅蓝斜向流光，增强渐变交融的眩晕感
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0x66A8D8FF), Color(0x00A8D8FF), Color(0x59FFE28A)],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 图片加载时的 Shimmer 占位效果。
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({required this.size, required this.borderRadius});

  final double size;
  final double borderRadius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainer;
    final highlightColor = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: .4)
        : Colors.white.withValues(alpha: .6);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(_animation.value - 0.5, 0),
                end: Alignment(_animation.value + 0.5, 0),
                colors: [baseColor, highlightColor, baseColor],
                stops: const [0, 0.5, 1],
              ),
            ),
            child: child,
          ),
        );
      },
      child: SizedBox(
        width: widget.size.isFinite ? widget.size : null,
        height: widget.size.isFinite ? widget.size : null,
      ),
    );
  }
}
