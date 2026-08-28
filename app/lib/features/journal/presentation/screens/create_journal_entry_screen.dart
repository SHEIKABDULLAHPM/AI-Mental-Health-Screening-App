import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/journal/data/journal_entry.dart';
import 'package:mindease/features/journal/presentation/state/journal_controller.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_snackbar.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';

/// Create a journal entry: text, voice or image, with an emotion-analysis
/// preview slot for the future AI phase.
class CreateJournalEntryScreen extends StatefulWidget {
  const CreateJournalEntryScreen({super.key});

  @override
  State<CreateJournalEntryScreen> createState() =>
      _CreateJournalEntryScreenState();
}

class _CreateJournalEntryScreenState extends State<CreateJournalEntryScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();

  int _mode = 0; // 0 text, 1 voice, 2 image, 3 video
  bool _recording = false;
  bool _saving = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _recordingStartTime;

  File? _imageFile;
  File? _audioFile;
  File? _videoFile;
  int? _audioDurationSeconds;
  int? _videoDurationSeconds;

  @override
  void dispose() {
    _durationTimer?.cancel();
    _title.dispose();
    _content.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _imageFile = File(picked.path));
      }
    } catch (e) {
      if (mounted) AppSnackbar.show(context, 'Failed to pick image: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (picked != null) {
        final file = File(picked.path);
        final size = await file.length();
        // 100 MB limit for video
        if (size > 100 * 1024 * 1024) {
          if (mounted) AppSnackbar.show(context, 'Video must be under 100 MB.');
          return;
        }
        setState(() => _videoFile = file);
      }
    } catch (e) {
      if (mounted) AppSnackbar.show(context, 'Failed to pick video: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) AppSnackbar.show(context, 'Microphone permission required.');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/journal_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: path,
      );
      _recordingStartTime = DateTime.now();
      setState(() {
        _recording = true;
        _recordingDuration = Duration.zero;
      });
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _recordingStartTime != null) {
          setState(
            () => _recordingDuration =
                DateTime.now().difference(_recordingStartTime!),
          );
        }
      });
    } catch (e) {
      if (mounted) AppSnackbar.show(context, 'Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _durationTimer?.cancel();
      _durationTimer = null;
      _recordingStartTime = null;
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          setState(() {
            _audioFile = file;
            _audioDurationSeconds = _recordingDuration.inSeconds;
          });
        }
      }
    } catch (e) {
      if (mounted) AppSnackbar.show(context, 'Failed to stop recording: $e');
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      AppSnackbar.show(context, 'Add a title first.');
      return;
    }
    final hasText = _content.text.trim().isNotEmpty;
    final hasImage = _imageFile != null;
    final hasAudio = _audioFile != null;
    final hasVideo = _videoFile != null;
    if (!hasText && !hasImage && !hasAudio && !hasVideo) {
      AppSnackbar.show(context, 'Add content, media, or a recording.');
      return;
    }

    setState(() => _saving = true);
    final controller = Provider.of<JournalController>(context, listen: false);
    final type = switch (_mode) {
      0 => JournalEntryType.text,
      1 => JournalEntryType.voice,
      2 => JournalEntryType.image,
      3 => JournalEntryType.video,
      _ => JournalEntryType.text,
    };
    final success = await controller.createEntry(
      title: _title.text.trim(),
      content: _content.text.trim(),
      type: type,
      imageFile: _imageFile,
      audioFile: _audioFile,
      audioDurationSeconds: _audioDurationSeconds,
      videoFile: _videoFile,
      videoDurationSeconds: _videoDurationSeconds,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) {
      AppSnackbar.show(context, 'Entry saved.');
      if (mounted) context.pop();
    } else {
      AppSnackbar.show(context, 'Failed to save entry. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FeatureScaffold(
      title: 'New entry',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Give this entry a name',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Entry type',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Text'),
                  icon: Icon(Icons.notes_rounded),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Voice'),
                  icon: Icon(Icons.mic_rounded),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('Image'),
                  icon: Icon(Icons.photo_rounded),
                ),
                ButtonSegment(
                  value: 3,
                  label: Text('Video'),
                  icon: Icon(Icons.videocam_rounded),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_mode == 1) _buildVoice(theme),
            if (_mode == 2) _buildImage(theme),
            if (_mode == 3) _buildVideo(theme),
            if (_mode == 1 || _mode == 2 || _mode == 3)
              const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _content,
              maxLines: _mode == 0 ? 8 : 4,
              decoration: InputDecoration(
                labelText: _mode == 0 ? 'How are you feeling?' : 'Add a note (optional)',
                hintText: _mode == 0
                    ? 'Write freely — this space is private to you.'
                    : 'Add context to this entry',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _AnalysisPlaceholder(),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: _mode == 0
                  ? 'Save Entry'
                  : _mode == 1
                      ? 'Save Voice Entry'
                      : _mode == 3
                          ? 'Save Video Entry'
                          : 'Save Image Entry',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildVoice(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Icon(
              _recording
                  ? Icons.graphic_eq_rounded
                  : (_audioFile != null
                      ? Icons.mic_rounded
                      : Icons.mic_none_rounded),
              size: 56,
              color: _recording
                  ? theme.colorScheme.error
                  : _audioFile != null
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _recording
                  ? 'Recording… tap to stop'
                  : _audioFile != null
                      ? 'Recording ready (${_recordingDuration.inSeconds}s)'
                      : 'Record your thoughts',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _recording
                  ? 'Keep going until you are ready to stop'
                  : _audioFile != null
                      ? 'Tap to re-record'
                      : 'Tap to start recording',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            IconButton.filled(
              tooltip: _recording ? 'Stop recording' : 'Start recording',
              style: IconButton.styleFrom(
                backgroundColor: _recording
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                minimumSize: const Size(64, 64),
              ),
              onPressed: _toggleRecording,
              icon: Icon(
                _recording ? Icons.stop_rounded : Icons.mic_rounded,
                size: 26,
              ),
            ),
            if (_recording)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  '${_recordingDuration.inMinutes}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            if (_imageFile != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  _imageFile!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Image ready',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Replace'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _imageFile = null),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 38,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Add a photo',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Choose from gallery or take a photo',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: const Text('Gallery'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.tonalIcon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded, size: 18),
                    label: const Text('Camera'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVideo(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            if (_videoFile != null) ...[
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Icon(Icons.videocam_rounded, size: 56),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Video ready',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Replace'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _videoFile = null),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.videocam_rounded,
                  size: 38,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Add a video',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Choose a video from your gallery (max 5 min, 100 MB)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonalIcon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.video_library_rounded, size: 18),
                label: const Text('Choose video'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Info card about AI analysis (runs automatically after save).
class _AnalysisPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI emotion analysis',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'After saving, your entry will be analysed for emotion, '
                    'sentiment, and a summary. Results appear in entry details.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
