import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/media/media_upload_service.dart';
import 'package:mindease/features/journal/data/journal_entry.dart';

/// Manages journal entries: listing, CRUD, search, pagination, media, and detail view.
class JournalController extends ChangeNotifier {
  JournalController(this._api, {MediaUploadService? mediaService})
      : _mediaService = mediaService;

  final FeatureApi _api;
  final MediaUploadService? _mediaService;

  List<JournalEntry> _entries = [];
  JournalEntry? _currentEntry;
  bool _loading = false;
  String? _error;
  bool _hasMore = true;
  int _currentPage = 0;
  static const int _pageSize = 20;
  bool _disposed = false;

  // Search & filter state
  String _searchQuery = '';
  String? _typeFilter;
  int _totalCount = 0;

  List<JournalEntry> get entries => _entries;
  JournalEntry? get currentEntry => _currentEntry;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get searchQuery => _searchQuery;
  String? get typeFilter => _typeFilter;
  int get totalCount => _totalCount;

  void _start() {
    _loading = true;
    _error = null;
    // `_start()` runs synchronously from loaders that screens call straight
    // out of `initState`. Notifying here would mark the provider scope while
    // the framework is still building that screen, which it rejects with
    // "setState() or markNeedsBuild() called during build". `_loading` is
    // already set, so the current build reads the right state; the deferred
    // notification just schedules the follow-up rebuild safely.
    if (_disposed) return;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _fail(Object e) {
    _error = e is Failure ? e.message : 'Something went wrong.';
    _loading = false;
    notifyListeners();
  }

  /// Load entries with optional search and filter (resets pagination).
  Future<void> loadEntries({
    String? search,
    String? type,
    bool reset = true,
  }) async {
    if (reset) {
      _currentPage = 0;
      _hasMore = true;
      _entries = [];
    }
    _searchQuery = search ?? _searchQuery;
    _typeFilter = type ?? _typeFilter;
    _start();
    try {
      final result = await _api.searchJournalEntries(
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        type: _typeFilter,
        page: _currentPage,
        size: _pageSize,
      );
      final entryRows = result['entries'] as List<dynamic>? ?? [];
      final newEntries =
          entryRows.map((e) => _fromApi(e as Map<String, dynamic>)).toList();
      _totalCount = (result['total'] as num?)?.toInt() ?? 0;
      if (reset) {
        _entries = newEntries;
      } else {
        _entries = [..._entries, ...newEntries];
      }
      _hasMore = newEntries.length >= _pageSize;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load next page (pagination).
  Future<void> loadMore() async {
    if (_loading || !_hasMore) return;
    _currentPage++;
    await loadEntries(reset: false);
  }

  /// Pull-to-refresh: reset and reload.
  Future<void> refreshEntries() async {
    await loadEntries(reset: true);
  }

  /// Create a new journal entry with optional media.
  Future<bool> createEntry({
    required String title,
    required String content,
    required JournalEntryType type,
    String? emotion,
    File? imageFile,
    File? audioFile,
    int? audioDurationSeconds,
    File? videoFile,
    int? videoDurationSeconds,
  }) async {
    _start();
    try {
      String? imageKey, imageContentType;
      int? imageSize;
      String? audioKey, audioContentType;
      int? audioSize;
      String? videoKey, videoContentType;
      int? videoSize;

      final svc = _mediaService;

      // Upload image if provided
      if (imageFile != null && svc != null) {
        final result = await svc.upload(
          file: imageFile,
          mediaType: 'IMAGE',
        );
        imageKey = result.key;
        imageContentType = result.contentType;
        imageSize = result.size;
      }

      // Upload audio if provided
      if (audioFile != null && svc != null) {
        final result = await svc.upload(
          file: audioFile,
          mediaType: 'AUDIO',
        );
        audioKey = result.key;
        audioContentType = result.contentType;
        audioSize = result.size;
      }

      // Upload video if provided
      if (videoFile != null && svc != null) {
        final result = await svc.upload(
          file: videoFile,
          mediaType: 'VIDEO',
        );
        videoKey = result.key;
        videoContentType = result.contentType;
        videoSize = result.size;
      }

      await _api.createJournalEntry(
        title: title,
        content: content,
        type: type.name,
        emotion: emotion,
        imageKey: imageKey,
        imageContentType: imageContentType,
        imageSize: imageSize,
        audioKey: audioKey,
        audioContentType: audioContentType,
        audioSize: audioSize,
        audioDurationSeconds: audioDurationSeconds,
        videoKey: videoKey,
        videoContentType: videoContentType,
        videoSize: videoSize,
        videoDurationSeconds: videoDurationSeconds,
      );
      await loadEntries(reset: true);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Load a single entry into [currentEntry].
  Future<void> loadEntry(String id, {bool silently = false}) async {
    if (!silently) _start();
    try {
      final json = await _api.getJournalEntry(id);
      _currentEntry = _fromApi(json);
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (!silently) _fail(e);
    }
  }

  /// Update an existing entry with optional media replacement.
  Future<bool> updateEntry({
    required String id,
    required String title,
    required String content,
    String? emotion,
    File? imageFile,
    File? audioFile,
    int? audioDurationSeconds,
    bool removeImage = false,
    bool removeAudio = false,
    bool removeVideo = false,
  }) async {
    _start();
    try {
      String? imageKey, imageContentType;
      int? imageSize;
      String? audioKey, audioContentType;
      int? audioSize;

      final svc = _mediaService;

      // Upload new image if provided
      if (imageFile != null && svc != null) {
        final result = await svc.upload(
          file: imageFile,
          mediaType: 'IMAGE',
        );
        imageKey = result.key;
        imageContentType = result.contentType;
        imageSize = result.size;
      }

      // Upload new audio if provided
      if (audioFile != null && svc != null) {
        final result = await svc.upload(
          file: audioFile,
          mediaType: 'AUDIO',
        );
        audioKey = result.key;
        audioContentType = result.contentType;
        audioSize = result.size;
      }

      await _api.updateJournalEntry(
        id: id,
        title: title,
        content: content,
        emotion: emotion,
        imageKey: imageKey,
        imageContentType: imageContentType,
        imageSize: imageSize,
        audioKey: audioKey,
        audioContentType: audioContentType,
        audioSize: audioSize,
        audioDurationSeconds: audioDurationSeconds,
        removeImage: removeImage,
        removeAudio: removeAudio,
        removeVideo: removeVideo,
      );
      await loadEntries(reset: true);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Delete an entry and refresh the list.
  Future<bool> deleteEntry(String id) async {
    _start();
    try {
      await _api.deleteJournalEntry(id);
      _currentEntry = null;
      _entries = _entries.where((e) => e.id != id).toList();
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }

  /// Update search query and reload.
  Future<void> search(String query) async {
    await loadEntries(search: query, reset: true);
  }

  /// Update type filter and reload.
  Future<void> filterByType(String? type) async {
    await loadEntries(type: type, reset: true);
  }

  /// Clear search and filter.
  Future<void> clearFilters() async {
    _searchQuery = '';
    _typeFilter = null;
    await loadEntries(reset: true);
  }

  /// Retry AI analysis for an entry that failed or is stale.
  Future<bool> retryAiAnalysis(String id) async {
    try {
      final json = await _api.retryJournalAnalysis(id);
      _currentEntry = _fromApi(json);
      _entries = _entries.map((e) => e.id == id ? _currentEntry! : e).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _fail(e);
      return false;
    }
  }
}

// ──────────────────────────────────────────── API → domain mapping

JournalEntry _fromApi(Map<String, dynamic> json) {
  final aiJson = json['aiAnalysis'] as Map<String, dynamic>?;
  return JournalEntry(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    date: _parseDate(json['createdAt']),
    type: _parseType(json['type']),
    emotion: json['emotion'] as String?,
    imageKey: json['imageKey'] as String?,
    imageContentType: json['imageContentType'] as String?,
    imageSize: (json['imageSize'] as num?)?.toInt(),
    imageUrl: json['imageUrl'] as String?,
    audioKey: json['audioKey'] as String?,
    audioContentType: json['audioContentType'] as String?,
    audioSize: (json['audioSize'] as num?)?.toInt(),
    audioDurationSeconds: (json['audioDurationSeconds'] as num?)?.toInt(),
    audioUrl: json['audioUrl'] as String?,
    videoKey: json['videoKey'] as String?,
    videoContentType: json['videoContentType'] as String?,
    videoSize: (json['videoSize'] as num?)?.toInt(),
    videoDurationSeconds: (json['videoDurationSeconds'] as num?)?.toInt(),
    videoUrl: json['videoUrl'] as String?,
    aiAnalysis: aiJson != null ? _parseAiAnalysis(aiJson) : null,
    contentVersion: (json['contentVersion'] as num?)?.toInt() ?? 1,
    updatedAt: _parseDate(json['updatedAt']),
  );
}

AiAnalysisData? _parseAiAnalysis(Map<String, dynamic> json) {
  final status = json['status'] as String?;
  if (status == null) return null;
  return AiAnalysisData(
    status: status,
    emotion: json['emotion'] as String?,
    emotionConfidence: (json['emotionConfidence'] as num?)?.toDouble(),
    sentiment: json['sentiment'] as String?,
    sentimentConfidence: (json['sentimentConfidence'] as num?)?.toDouble(),
    emotionalThemes: json['emotionalThemes'] as String?,
    summary: json['summary'] as String?,
    reflectionPrompt: json['reflectionPrompt'] as String?,
  );
}

DateTime _parseDate(dynamic value) {
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

JournalEntryType _parseType(dynamic value) {
  final raw = (value as String?) ?? 'text';
  return JournalEntryType.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => JournalEntryType.text,
  );
}
