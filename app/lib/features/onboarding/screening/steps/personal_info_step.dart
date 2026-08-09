import 'package:flutter/material.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/core/utils/validators.dart';
import 'package:mindease/shared/widgets/app_text_field.dart';
import 'package:mindease/features/onboarding/screening/screening_controller.dart';

/// Step 1 — age, gender, and occupation.
class PersonalInfoStep extends StatefulWidget {
  const PersonalInfoStep({super.key, required this.controller});

  final ScreeningController controller;

  @override
  State<PersonalInfoStep> createState() => _PersonalInfoStepState();
}

class _PersonalInfoStepState extends State<PersonalInfoStep> {
  static const _genderOptions = [
    'Female',
    'Male',
    'Non-binary',
    'Prefer not to say',
  ];

  static const _occupations = [
    'Student',
    'Employed full-time',
    'Working part-time',
    'Self-employed',
    'Homemaker',
    'Retired',
    'Unemployed',
    'Prefer not to say',
  ];

  late final TextEditingController _age;
  String? _ageError;

  String get _gender => widget.controller.personal.gender;
  String get _occupation => widget.controller.personal.occupation;

  @override
  void initState() {
    super.initState();
    _age = TextEditingController(text: widget.controller.personal.age);
  }

  @override
  void dispose() {
    _age.dispose();
    super.dispose();
  }

  void _onAgeChanged(String value) {
    _ageError = Validators.age(value);
    widget.controller.setPersonal(age: value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us a little about yourself',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _FieldLabel('Age'),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _age,
            hint: 'e.g. 24',
            prefixIcon: Icons.cake_outlined,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            errorText: _ageError,
            onChanged: _onAgeChanged,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _FieldLabel('Gender'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final g in _genderOptions)
                ChoiceChip(
                  label: Text(g),
                  selected: _gender == g,
                  onSelected: (_) {
                    widget.controller.setPersonal(gender: g);
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _FieldLabel('Occupation'),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _occupation.isEmpty ? null : _occupation,
            isExpanded: true,
            hint: const Text('Select your occupation'),
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.work_outline_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            items: [
              for (final o in _occupations)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) {
              widget.controller.setPersonal(occupation: v ?? '');
              setState(() {});
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'This information helps us personalise your wellness profile.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}
