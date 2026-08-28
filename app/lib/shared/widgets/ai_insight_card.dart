import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';

/// A reusable card that renders AI-generated text insights in a structured,
/// professional format. Parses plain-text paragraphs into a header, summary,
/// and supporting bullet points for clear readability.
///
/// Used across dashboard insights, mood guidance, journal analysis,
/// and recommendation explanations.
class AIInsightCard extends StatelessWidget {
  const AIInsightCard({
    super.key,
    required this.title,
    required this.text,
    this.icon = Icons.auto_awesome_rounded,
    this.iconColor,
    this.backgroundColor,
    this.titleStyle,
    this.textStyle,
    this.showBullets = true,
    this.compact = false,
  });

  /// Card header label (e.g. "Today's AI Insight", "Suggested for today").
  final String title;

  /// The raw AI-generated insight text. May contain multiple sentences
  /// or paragraphs separated by newlines.
  final String text;

  /// Leading icon in the header.
  final IconData icon;

  /// Override color for the header icon and title.
  final Color? iconColor;

  /// Override background color for the card.
  final Color? backgroundColor;

  /// Override the title text style.
  final TextStyle? titleStyle;

  /// Override the body text style.
  final TextStyle? textStyle;

  /// Whether to render subsequent sentences as bullet points.
  /// When false, all text is shown as a single paragraph.
  final bool showBullets;

  /// Compact mode: smaller padding, no bullets, just a header + paragraph.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.primary;
    final parsed = _InsightParser.parse(text);

    if (compact) {
      return _CompactInsight(
        title: title,
        text: text,
        icon: icon,
        color: color,
        theme: theme,
        titleStyle: titleStyle,
        textStyle: textStyle,
      );
    }

    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: titleStyle ??
                        theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                  ),
                ),
              ],
            ),

            // ── Summary (first sentence) ──
            if (parsed.summary.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                parsed.summary,
                style: textStyle ??
                    theme.textTheme.bodyMedium?.copyWith(
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],

            // ── Bullet points (remaining sentences) ──
            if (showBullets && parsed.bullets.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              ...parsed.bullets.map(
                (bullet) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 7),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          bullet,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact variant for recommendation cards and inline usage.
class _CompactInsight extends StatelessWidget {
  const _CompactInsight({
    required this.title,
    required this.text,
    required this.icon,
    required this.color,
    required this.theme,
    this.titleStyle,
    this.textStyle,
  });

  final String title;
  final String text;
  final IconData icon;
  final Color color;
  final ThemeData theme;
  final TextStyle? titleStyle;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: titleStyle ??
                      theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: textStyle ??
                theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

/// Parsed insight text broken into a summary and optional bullet points.
class _InsightParser {
  final String summary;
  final List<String> bullets;

  const _InsightParser({required this.summary, required this.bullets});

  /// Parse a raw insight string into summary + bullets.
  ///
  /// Splitting rules:
  /// - The first sentence (up to the first period/question mark/exclamation)
  ///   becomes the summary.
  /// - Remaining sentences become bullet points.
  /// - Sentences separated by newlines are treated as distinct items.
  /// - Sentences shorter than 10 characters are merged into the previous bullet.
  static _InsightParser parse(String raw) {
    if (raw.trim().isEmpty) {
      return const _InsightParser(summary: '', bullets: []);
    }

    // Split by newlines first, then by sentence boundaries
    final allSentences = <String>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Split by sentence-ending punctuation followed by space or end
      final parts = trimmed.split(RegExp(r'(?<=[.!?])\s+'));
      for (final part in parts) {
        final s = part.trim();
        if (s.isNotEmpty) allSentences.add(s);
      }
    }

    if (allSentences.isEmpty) {
      return const _InsightParser(summary: '', bullets: []);
    }

    final summary = allSentences.first;
    final bullets = <String>[];

    for (var i = 1; i < allSentences.length; i++) {
      final sentence = allSentences[i];
      if (sentence.length < 10 && bullets.isNotEmpty) {
        // Very short fragment — merge with previous bullet
        bullets.last = '${bullets.last} $sentence';
      } else {
        bullets.add(sentence);
      }
    }

    return _InsightParser(summary: summary, bullets: bullets);
  }
}
