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
    // 全幅场景（播放页传 size 无限大）按屏幕短边取比例，其余按容器边长等比缩放，
    // 保证吉祥物在大封面上协调、在小列表项里不溢出。
    final double imageExtent;
    if (size.isFinite) {
      imageExtent = (size * 0.68).clamp(28.0, 300.0);
    } else {
      final shortestSide = MediaQuery.sizeOf(context).shortestSide;
      imageExtent = (shortestSide * 0.5).clamp(96.0, 280.0);
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFD9BE),
            Color(0xFFFFEFE6),
            Color(0xFFFCE3D4),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 液态玻璃磨砂质感：左上柔光 + 右下暖调弥散 + 斜向玻璃高光
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
}

/// 液态玻璃磨砂高光层：纯装饰性叠层，模拟玻璃的柔光、弥散与斜向反光。
class _GlassSheen extends StatelessWidget {
  const _GlassSheen();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 左上角白色柔光（玻璃受光面）
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.7, -0.8),
                radius: 1.1,
                colors: [Color(0x8FFFFFFF), Color(0x00FFFFFF)],
              ),
            ),
          ),
          // 右下角暖杏弥散光晕（液态流动感）
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.8, 0.9),
                radius: 1.0,
                colors: [Color(0x66FFC49B), Color(0x00FFC49B)],
              ),
            ),
          ),
          // 斜向玻璃反光条
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment(0.1, 0.55),
                colors: [
                  Color(0x59FFFFFF),
                  Color(0x14FFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: [0, 0.45, 0.8],
              ),
            ),
          ),
        ],
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
