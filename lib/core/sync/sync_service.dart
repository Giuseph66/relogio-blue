import 'package:flutter/foundation.dart';
import '../auth/auth_service.dart';
import 'dart:async';

import '../logger/app_logger.dart';
import '../network/connectivity_service.dart';
import '../offline/offline_question_cache.dart';
import '../../features/profile/data/profile_service.dart';
import '../../features/history/data/repositories/watch_response_repository.dart';

/// Listens for connectivity changes and triggers a sync of pending
/// watch responses whenever the device comes back online.
class SyncService {
  final WatchResponseRepository _repository;
  final ConnectivityService _connectivity;
  final String Function() _serverUrlProvider;

  StreamSubscription<bool>? _sub;
  bool _isSyncing = false;

  SyncService({
    required WatchResponseRepository repository,
    required ConnectivityService connectivity,
    required String Function() serverUrlProvider,
  })  : _repository = repository,
        _connectivity = connectivity,
        _serverUrlProvider = serverUrlProvider;

  /// Start listening for network changes.
  void start() {
    _sub?.cancel();
    _sub = _connectivity.isOnline.listen((online) async {
      if (!online) return;
      unawaited(ProfileService().sync());
      if (_isSyncing) return;
      if (kIsWeb && !AuthService().hasAppSession) return;
      final url = _serverUrlProvider();
      if (url.isEmpty) return;
      _isSyncing = true;
      AppLogger.info('SyncService: online — syncing pending responses');
      try {
        await _repository.syncPending(url);
        // Back online: refresh locations/questions used when offline.
        await OfflineQuestionCache().refresh(baseUrl: url);
      } finally {
        _isSyncing = false;
      }
    });
    AppLogger.info('SyncService: started');
  }

  /// Trigger a manual sync (e.g., called from a UI button).
  Future<void> syncNow() async {
    unawaited(ProfileService().sync());
    if (_isSyncing) return;
    final url = _serverUrlProvider();
    if (url.isEmpty) return;
    _isSyncing = true;
    try {
      await _repository.syncPending(url);
    } finally {
      _isSyncing = false;
    }
  }

  /// Stop listening. Call in dispose.
  void dispose() {
    _sub?.cancel();
    _sub = null;
    AppLogger.info('SyncService: stopped');
  }
}
