import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import 'package:mindease/core/theme/app_spacing.dart';
import 'package:mindease/features/journal/presentation/state/journal_controller.dart';
import 'package:mindease/shared/widgets/app_button.dart';
import 'package:mindease/shared/widgets/app_snackbar.dart';
import 'package:mindease/shared/widgets/feature_scaffold.dart';
import 'package:mindease/shared/widgets/state_views.dart';

/// Edit an existing journal entry with media support and unsaved content protection.
class EditJournalEntryScreen extends StatefulWidget {
  const EditJournalEntryScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<EditJournalEntryScreen> createState() => _EditJournalEntryScreenState();
}

class _EditJournalEntryScreenState extends State<EditJournalEntryScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();

  bool _saving = false;
  bool _loading = true;
  String? _error;

  // Current media state
  String? _currentEmotion;
  File? _newImageFile;
  String? _existingImageKey;
  String? _existingImageUrl;
  bool _removeImage = false;

  File? _newAudioFile;
  String? _existingAudioKey;
  String? _existingAudioUrl;
  bool _removeAudio = false;
  bool _recording = false;

  String? _existingVideoKey;
  String? _existingVideoUrl;
  int? _existingVideoDuration;
  int? _existingVideoSize;
  bool _removeVideo = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _recordingStartTime;
  int? _audioDurationSeconds;

  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _loadEntry();
    _title.addListener(_checkUnsavedChanges);
    _content.addListener(_checkUnsavedChanges);
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _title.removeListener(_checkUnsavedChanges);
    _content.removeListener(_checkUnsavedChanges);
    _title.dispose();
    _content.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _checkUnsavedChanges() {
    final controller = Provider.of<JournalController>(context, listen: false);
    final original = controller.currentEntry;
    if (original == null) return;

    final changed = _title.text.trim() != original.title ||
        _content.text.trim() != original.content ||
        _currentEmotion != original.emotion ||
        _newImageFile != null ||
        _removeImage ||
        _newAudioFile != null ||
        _removeAudio ||
        _removeVideo;

    if (changed != _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = changed);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have unsaved changes. Do you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _loadEntry() async {
    final controller = Provider.of<JournalController>(context, listen: false);
    await controller.loadEntry(widget.entryId);
    if (!mounted) return;

    final entry = controller.currentEntry;
    if (entry == null) {
      setState(() {
        _loading = false;
        _error = 'Entry not found';
      });
      return;
    }

    setState(() {
      _title.text = entry.title;
      _content.text = entry.content;
      _currentEmotion = entry.emotion;
      _existingImageKey = entry.hasImage ? entry.imageKey : null;
      _existingImageUrl = entry.imageUrl;
      _existingAudioKey = entry.hasAudio ? entry.audioKey : null;
      _existingAudioUrl = entry.audioUrl;
      _audioDurationSeconds = entry.audioDurationSeconds;
      _existingVideoKey = entry.hasVideo ? entry.videoKey : null;
      _existingVideoUrl = entry.videoUrl;
      _existingVideoDuration = entry.videoDurationSeconds;
      _existingVideoSize = entry.videoSize;
      _loading = false;
    });
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
        setState(() {
          _newImageFile = File(picked.path);
          _removeImage = false;
          _hasUnsavedChanges = true;
        });
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, 'Failed to pick image: $e');
      }
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
      if (mounted) {
        AppSnackbar.show(
          context,
          'Microphone permission is required to record.',
        );
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/journal_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

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
      if (mounted) {
        AppSnackbar.show(context, 'Failed to start recording: $e');
      }
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
            _newAudioFile = file;
            _removeAudio = false;
            _audioDurationSeconds = _recordingDuration.inSeconds;
            _hasUnsavedChanges = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, 'Failed to stop recording: $e');
      }
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      AppSnackbar.show(context, 'Title is required.');
      return;
    }
    if (_content.text.trim().isEmpty &&
        _newImageFile == null &&
        !_removeImage &&
        _existingImageKey == null &&
        _newAudioFile == null &&
        !_removeAudio &&
        _existingAudioKey == null) {
      AppSnackbar.show(context, 'Add some content to save.');
      return;
    }

    setState(() => _saving = true);

    final controller = Provider.of<JournalController>(context, listen: false);
    final success = await controller.updateEntry(
      id: widget.entryId,
      title: _title.text.trim(),
      content: _content.text.trim(),
      emotion: _currentEmotion,
      imageFile: _newImageFile,
      audioFile: _newAudioFile,
      audioDurationSeconds: _audioDurationSeconds,
      removeImage: _removeImage,
      removeAudio: _removeAudio,
      removeVideo: _removeVideo,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      AppSnackbar.show(context, 'Entry updated.');
      context.pop();
    } else {
      AppSnackbar.show(context, 'Failed to update entry. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) context.pop();
        }
      },
      child: FeatureScaffold(
        title: 'Edit entry',
        body: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorStateView(
                    title: 'Entry not found',
                    message: _error!,
                    onRetry: () {
                      setState(() {});
                      _loadEntry();
                    },
                  )
                : SingleChildScrollView(
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
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _content,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'How are you feeling?',
                            hintText:
                                'Write freely — this space is private to you.',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // ── Media section ──
                        _MediaSection(
                          newImageFile: _newImageFile,
                          existingImageKey: _existingImageKey,
                          existingImageUrl: _existingImageUrl,
                          removeImage: _removeImage,
                          newAudioFile: _newAudioFile,
                          existingAudioKey: _existingAudioKey,
                          existingAudioUrl: _existingAudioUrl,
                          existingAudioDuration: _audioDurationSeconds,
                          removeAudio: _removeAudio,
                          existingVideoKey: _existingVideoKey,
                          existingVideoUrl: _existingVideoUrl,
                          existingVideoDuration: _existingVideoDuration,
                          existingVideoSize: _existingVideoSize,
                          removeVideo: _removeVideo,
                          recording: _recording,
                          recordingDuration: _recordingDuration,
                          onPickImage: _pickImage,
                          onRemoveImage: () => setState(() {
                            _removeImage = true;
                            _newImageFile = null;
                            _hasUnsavedChanges = true;
                          }),
                          onToggleRecording: _toggleRecording,
                          onRemoveAudio: () => setState(() {
                            _removeAudio = true;
                            _newAudioFile = null;
                            _hasUnsavedChanges = true;
                          }),
                          onRemoveVideo: () => setState(() {
                            _removeVideo = true;
                            _hasUnsavedChanges = true;
                          }),
                        ),

                        const SizedBox(height: AppSpacing.xl),
                        AppButton(
                          label: 'Save Changes',
                          icon: Icons.check_rounded,
                          loading: _saving,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// Media section showing current image/audio/video with actions.
class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.newImageFile,
    required this.existingImageKey,
    required this.existingImageUrl,
    required this.removeImage,
    required this.newAudioFile,
    required this.existingAudioKey,
    required this.existingAudioUrl,
    this.existingAudioDuration,
    required this.removeAudio,
    required this.recording,
    required this.recordingDuration,
    required this.onPickImage,
    required this.onRemoveImage,
    required this.onToggleRecording,
    required this.onRemoveAudio,
    this.existingVideoKey,
    this.existingVideoUrl,
    this.existingVideoDuration,
    this.existingVideoSize,
    required this.removeVideo,
    required this.onRemoveVideo,
  });

  final File? newImageFile;
  final String? existingImageKey;
  final String? existingImageUrl;
  final bool removeImage;
  final File? newAudioFile;
  final String? existingAudioKey;
  final String? existingAudioUrl;
  final int? existingAudioDuration;
  final bool removeAudio;
  final bool recording;
  final Duration recordingDuration;
  final void Function(ImageSource) onPickImage;
  final VoidCallback onRemoveImage;
  final VoidCallback onToggleRecording;
  final VoidCallback onRemoveAudio;
  final String? existingVideoKey;
  final String? existingVideoUrl;
  final int? existingVideoDuration;
  final int? existingVideoSize;
  final bool removeVideo;
  final VoidCallback onRemoveVideo;

  static String _formatExistingDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '0s';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return min > 0 ? '${min}m ${sec}s' : '${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCurrentImage =
        newImageFile != null || (existingImageKey != null && !removeImage);
    final hasCurrentAudio =
        newAudioFile != null || (existingAudioKey != null && !removeAudio);
    final hasCurrentVideo =
        existingVideoKey != null && !removeVideo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Image ──
        Text(
          'Image',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (hasCurrentImage)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  if (newImageFile != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        newImageFile!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  else if (existingImageUrl != null &&
                      existingImageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        existingImageUrl!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.image_rounded,
                              size: 32,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.image_rounded,
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => onPickImage(ImageSource.gallery),
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text('Replace'),
                      ),
                      TextButton.icon(
                        onPressed: onRemoveImage,
                        icon:
                            const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Remove'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => onPickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded, size: 18),
                label: const Text('Gallery'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => onPickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                label: const Text('Camera'),
              ),
            ],
          ),

        const SizedBox(height: AppSpacing.lg),

        // ── Audio ──
        Text(
          'Voice recording',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (hasCurrentAudio)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.mic_rounded,
                    color: theme.colorScheme.tertiary,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(                            recording
                          ? 'Recording: ${recordingDuration.inMinutes}:${(recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}'
                          : newAudioFile != null
                              ? 'New recording (${_formatExistingDuration(existingAudioDuration)})'
                              : 'Existing recording${existingAudioDuration != null && existingAudioDuration! > 0 ? ' (${_formatExistingDuration(existingAudioDuration)})' : ''}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onRemoveAudio,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  IconButton.filled(
                    onPressed: onToggleRecording,
                    style: IconButton.styleFrom(
                      backgroundColor: recording
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      minimumSize: const Size(56, 56),
                    ),
                    icon: Icon(
                      recording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    recording ? 'Tap to stop' : 'Tap to record',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (recording)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        '${recordingDuration.inMinutes}:${(recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        // ── Video ──
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Video',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (hasCurrentVideo)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.videocam_rounded,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Video recording',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _formatExistingDuration(existingVideoDuration),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onRemoveVideo,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.videocam_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  'No video attached',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
