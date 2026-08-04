import 'package:flutter/material.dart';

class AppIndeterminateBar extends StatefulWidget {
  const AppIndeterminateBar({
    super.key,
    this.height = 10,
    this.color,
    this.trackColor,
    this.width = double.infinity,
  });

  final double height;
  final Color? color;
  final Color? trackColor;
  final double width;

  @override
  State<AppIndeterminateBar> createState() => _AppIndeterminateBarState();
}

class _AppIndeterminateBarState extends State<AppIndeterminateBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fullWidth = constraints.maxWidth;
          final pillWidth = fullWidth * 0.38;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final pos = t < 0.5 ? t / 0.5 : (1 - t) / 0.5;
              final left = (fullWidth - pillWidth) * pos;
              return ClipRRect(
                borderRadius: BorderRadius.circular(widget.height),
                child: Stack(
                  children: [
                    Container(
                      height: widget.height,
                      width: fullWidth,
                      color: widget.trackColor ?? color.withValues(alpha: 0.12),
                    ),
                    Positioned(
                      left: left,
                      top: 0,
                      bottom: 0,
                      width: pillWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withValues(alpha: 0.6),
                              color,
                              Color.lerp(color, Colors.white, 0.3)!,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(widget.height),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
