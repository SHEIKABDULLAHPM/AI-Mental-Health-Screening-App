import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/future_letters/presentation/state/future_letter_controller.dart';
import 'package:mindease/shared/widgets/app_text_field.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Compose a letter to your future self with a delivery date.
class CreateFutureLetterScreen extends StatefulWidget {
  const CreateFutureLetterScreen({super.key});

  @override
  State<CreateFutureLetterScreen> createState() =>
      _CreateFutureLetterScreenState();
}

class _CreateFutureLetterScreenState extends State<CreateFutureLetterScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  DateTime _delivery = DateTime.now().add(const Duration(days: 30));

  bool get _canSave =>
      _title.text.trim().isNotEmpty && _content.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _delivery,
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null && mounted) {
      setState(() => _delivery = picked);
    }
  }

  void _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = context.read<FutureLetterController>();
    await ctrl.createLetter(
      title: _title.text.trim(),
      recipient: 'future self',
      scheduledDate: _delivery,
      content: _content.text.trim(),
    );
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Letter scheduled for ${_delivery.year}-${_delivery.month.toString().padLeft(2, '0')}-${_delivery.day.toString().padLeft(2, '0')}',
          ),
        ),
      );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FeatureScaffold(
      title: 'Write a letter',
      body: FeatureBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: _title,
              hint: 'Title (e.g. To my future self)',
              prefixIcon: Icons.mail_outline_rounded,
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Deliver on'),
                subtitle: Text(
                  '${_delivery.year}-${_delivery.month.toString().padLeft(2, '0')}-${_delivery.day.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Your letter',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _content,
              maxLines: 8,
              minLines: 6,
              decoration: const InputDecoration(
                hintText:
                    'What do you want to remind yourself on that day?…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Letters are stored securely and delivered privately to you.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _canSave ? _save : null,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Schedule letter'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
