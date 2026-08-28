import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/habits/data/habit_constants.dart';
import 'package:mindease/features/habits/presentation/state/habit_controller.dart';
import 'package:mindease/shared/widgets/app_text_field.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Create a new habit: pick icon + accent, set a goal.
class AddHabitScreen extends StatefulWidget {
  const AddHabitScreen({super.key});

  @override
  State<AddHabitScreen> createState() => _AddHabitScreenState();
}

class _AddHabitScreenState extends State<AddHabitScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _goal = TextEditingController();
  int _iconIndex = 0;
  int _colorIndex = 0;

  bool get _canSave =>
      _title.text.trim().isNotEmpty && _goal.text.trim().isNotEmpty;

  void _save() {
    final controller = Provider.of<HabitController>(context, listen: false);
    controller.createHabit(
      title: _title.text.trim(),
      iconCodePoint: kHabitIcons[_iconIndex].codePoint,
      colorValue: kHabitColors[_colorIndex].toARGB32(),
      goalLabel: _goal.text.trim(),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Habit "${_title.text.trim()}" created')),
      );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FeatureScaffold(
      title: 'New habit',
      body: FeatureBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor:
                          kHabitColors[_colorIndex].withValues(alpha: 0.15),
                      child: Icon(
                        kHabitIcons[_iconIndex],
                        color: kHabitColors[_colorIndex],
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        _title.text.trim().isEmpty
                            ? 'Give it a name…'
                            : _title.text.trim(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Habit name',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _title,
              hint: 'e.g. Journal before bed',
              prefixIcon: Icons.edit_rounded,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Daily goal',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _goal,
              hint: 'e.g. 10 minutes',
              prefixIcon: Icons.schedule_rounded,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Icon',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < kHabitIcons.length; i++)
                  ChoiceChip(
                    avatar: Icon(kHabitIcons[i], size: 18),
                    label: const Text(''),
                    selected: _iconIndex == i,
                    onSelected: (_) => setState(() => _iconIndex = i),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Accent',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var i = 0; i < kHabitColors.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _colorIndex = i),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: kHabitColors[i],
                          shape: BoxShape.circle,
                          border: _colorIndex == i
                              ? Border.all(
                                  color: theme.colorScheme.onSurface,
                                  width: 2,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _save : null,
                child: const Text('Create habit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
