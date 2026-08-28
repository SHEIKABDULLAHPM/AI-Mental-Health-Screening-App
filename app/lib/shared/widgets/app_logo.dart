import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Brand icon: the exact logomark from the brand artwork.
///
/// Reserved for compact / icon-only spots.
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SvgPicture.asset(
        'assets/logo/logo.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Brand lockup: the logo with the SYNORA name / tagline (branding spots).
///
/// Rendered from the vector artwork so it stays crisp at any size and the
/// proportions always match the source (1342x894).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 56, this.showTagline = false});

  /// Display width of the lockup; height follows the artwork's exact ratio.
  final double size;

  /// The lockup artwork already includes the tagline, so this flag is only
  /// kept for call-site compatibility.
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SvgPicture.asset(
        'assets/logo/logo.svg',
        width: size,
        height: size * 894 / 1342,
        fit: BoxFit.contain,
      ),
    );
  }
}