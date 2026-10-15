import 'dart:ui';
import 'package:flutter/material.dart';

/// 毛玻璃效果工具类
class Glass {
  /// 毛玻璃容器
  /// [blur] 模糊强度
  /// [opacity] 不透明度（0~1，越小越透明）
  /// [radius] 圆角
  /// [tint] 染色（一般为半透明白/黑）
  static Widget box({
    required Widget child,
    double blur = 20,
    double opacity = 0.6,
    double radius = 16,
    Color? tint,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Border? border,
  }) {
    final isDark = _isDarkFromContext();
    final bg = tint ??
        (isDark
            ? Colors.white.withOpacity(0.08 * opacity)
            : Colors.white.withOpacity(0.55 * opacity));
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur.clamp(0.0, 8.0).toDouble(), sigmaY: blur.clamp(0.0, 8.0).toDouble()),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
              border: border ??
                  Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.4),
                    width: 0.5,
                  ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  /// 毛玻璃 AppBar 背景
  static Widget appBar({double blur = 25, double opacity = 0.7}) {
    final isDark = _isDarkFromContext();
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur.clamp(0.0, 8.0).toDouble(), sigmaY: blur.clamp(0.0, 8.0).toDouble()),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withOpacity(0.4 * opacity)
              : Colors.white.withOpacity(0.65 * opacity),
        ),
      ),
    );
  }

  static bool _isDarkFromContext() {
    // 无法直接拿 context，这里返回 false 占位，实际使用时由调用方传 tint
    return false;
  }
}

/// 需要主题感知时使用此变体（传 isDark）
class GlassBox extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool isDark;
  final Border? border;

  const GlassBox({
    super.key,
    required this.child,
    this.blur = 20,
    this.opacity = 0.6,
    this.radius = 16,
    this.padding,
    this.margin,
    this.isDark = false,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? Colors.white.withOpacity(0.08 * opacity)
        : Colors.white.withOpacity(0.55 * opacity);
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur.clamp(0.0, 8.0).toDouble(), sigmaY: blur.clamp(0.0, 8.0).toDouble()),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
              border: border ??
                  Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.4),
                    width: 0.5,
                  ),
            ),
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    );
  }
}
