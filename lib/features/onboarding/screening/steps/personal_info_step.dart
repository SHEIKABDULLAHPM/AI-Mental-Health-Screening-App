import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_section_card.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../screening_controller.dart';

class PersonalInfoStep extends StatefulWidget {
  const PersonalInfoStep({
    super.key,
    required this.controller,
    required this.onValidChanged,
  });

  final ScreeningController controller;
  final ValueChanged<bool> onValidChanged;

  @override
  State<PersonalInfoStep> createState() => _PersonalInfoStepState();
}

class _PersonalInfoStepState extends State<PersonalInfoStep> {
  static const List<String> _genderOptions = [
    'Female',
    'Male',
    'Non-binary',
    'Prefer not to say',
  ];

  late final TextEditingController _ageController;
  late final TextEditingController _occupationController;
  String? _gender;
  String? _ageError;
  bool _ageTouched = false;

  @override
  void initState() {
    super.initState();
    _ageController = TextEditingController(
      text: widget.controller.personal.age,
    );
    _occupationController = TextEditingController(
      text: widget.controller.personal.occupation,
    );
    _gender = widget.controller.personal.gender.isEmpty
        ? null
        : widget.controller.personal.gender;
  }

  @override
  void dispose() {
    _ageController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  void _sync({bool validateAge = false}) {
    if (validateAge) {
      _ageTouched = true;
      setState(() => _ageError = Validators.age(_ageController.text));
    }
    widget.controller.setPersonal(
      age: _ageController.text.trim(),
      gender: _gender ?? '',
      occupation: _occupationController.text.trim(),
    );
    final ageValid = _ageError == null;
    widget.onValidChanged(widget.controller.personal.isComplete && ageValid);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _ageController,
          label: 'Age',
          hintText: 'e.g. 28',
          prefixIcon: Icons.cake_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          errorText: _ageTouched ? _ageError : null,
          onChanged: (_) => _sync(validateAge: true),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Gender',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _genderOptions.map((option) {
            final selected = _gender == option;
            return GestureDetector(
              onTap: () {
                setState(() => _gender = option);
                _sync();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: Text(
                  option,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          controller: _occupationController,
          label: 'Occupation',
          hintText: 'e.g. Software Engineer',
          prefixIcon: Icons.work_outline_rounded,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onChanged: (_) => _sync(),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppSectionCard(
          color: AppColors.info.withValues(alpha: 0.08),
          borderColor: AppColors.info.withValues(alpha: 0.25),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: AppColors.info,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'This information helps personalize your assessment and the guidance you receive.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.info,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
