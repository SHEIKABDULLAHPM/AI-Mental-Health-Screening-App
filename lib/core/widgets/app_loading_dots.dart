import 'package:flutter/material.dart';

class AppLoadingDots extends StatefulWidget {
  const AppLoadingDots({super.key, this.color, this.dotSize = 9});

  final Color? color;
  final double dotSize;

  @override
  State<AppLoadingDots> createState() => _AppLoadingDotsState();
}

class _AppLoadingDotsState extends State<AppLoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final t = (_controller.value - index * 0.22) % 1.0;
            final scale = t < 0.5 ? 0.4 + 1.1 * t : 1.0 - 1.1 * (t - 0.5);
            final s = scale.clamp(0.35, 1.0).toDouble();
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.dotSize * 0.32),
              child: Transform.scale(
                scale: s,
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: s),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
