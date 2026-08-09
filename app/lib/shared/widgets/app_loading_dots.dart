import 'package:flutter/material.dart';

/// Three bouncing dots used for "working" states.
class AppLoadingDots extends StatefulWidget {
  const AppLoadingDots({
    super.key,
    this.color,
    this.size = 10,
    this.spacing = 10,
    this.duration = const Duration(milliseconds: 900),
  });

  final Color? color;
  final double size;
  final double spacing;
  final Duration duration;

  @override
  State<AppLoadingDots> createState() => _AppLoadingDotsState();
}

class _AppLoadingDotsState extends State<AppLoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

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
            final phase = (_controller.value + index / 3) % 1.0;
            final scale =
                0.6 + 0.4 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.35 + 0.65 * scale),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

/// An indeterminate shimmering progress bar used during AI processing.
class AppIndeterminateBar extends StatefulWidget {
  const AppIndeterminateBar({
    super.key,
    this.color,
    this.height = 6,
    this.duration = const Duration(milliseconds: 1400),
  });

  final Color? color;
  final double height;
  final Duration duration;

  @override
  State<AppIndeterminateBar> createState() => _AppIndeterminateBarState();
}

class _AppIndeterminateBarState extends State<AppIndeterminateBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final align = -1 + 2 * ((2 * _controller.value) % 1.0);
            return FractionallySizedBox(
              widthFactor: 0.45,
              alignment: Alignment(align, 0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.1),
                      color,
                      color.withValues(alpha: 0.1),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
