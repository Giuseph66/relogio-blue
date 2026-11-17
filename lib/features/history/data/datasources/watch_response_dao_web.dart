import '../../../../core/platform/browser_bridge.dart';
import '../../domain/entities/watch_response.dart';

class WatchResponseDao {
  Future<void> insert(WatchResponse response) async {
    await BrowserBridge.call('db.put', {
      'store': 'responses',
      'value': response.toMap(),
    });
  }

  Future<WatchResponse?> getById(String id) async {
    final value = await BrowserBridge.call('db.get', {
      'store': 'responses',
      'id': id,
    });
    return value == null
        ? null
        : WatchResponse.fromMap(Map<String, dynamic>.from(value as Map));
  }

  Future<List<WatchResponse>> getAll() async {
    final rows =
        await BrowserBridge.call('db.all', {'store': 'responses'}) as List;
    return rows
        .map((r) => WatchResponse.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<List<WatchResponse>> getPending() async {
    return (await getAll())
        .where(
          (r) =>
              r.questionStatus == QuestionStatus.answered &&
              r.syncStatus != SyncStatus.synced,
        )
        .toList()
        .reversed
        .toList();
  }

  Future<WatchResponse?> findLatestUnanswered(String questionId) async {
    for (final row in await getAll()) {
      if (row.questionId == questionId &&
          row.questionStatus != QuestionStatus.answered)
        return row;
    }
    return null;
  }

  Future<void> updateStatus(String id, SyncStatus status) async {
    await BrowserBridge.call('db.patch', {
      'store': 'responses',
      'id': id,
      'patch': {'sync_status': status.name},
    });
  }

  Future<void> markAnswered(String id, String answerId) async {
    await BrowserBridge.call('db.patch', {
      'store': 'responses',
      'id': id,
      'patch': {
        'question_status': QuestionStatus.answered.name,
        'answer_id': answerId,
        'sync_status': SyncStatus.pending.name,
      },
    });
  }

  Future<void> deleteAll() async {
    await BrowserBridge.call('db.clear', {'store': 'responses'});
  }
}
