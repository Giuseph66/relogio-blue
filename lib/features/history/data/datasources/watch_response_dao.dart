import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/watch_response.dart';

/// Data Access Object for [WatchResponse].
class WatchResponseDao {
  final AppDatabase _appDb;

  WatchResponseDao({AppDatabase? appDb}) : _appDb = appDb ?? AppDatabase();

  Future<Database> get _db async => _appDb.db;

  Future<void> insert(WatchResponse response) async {
    final db = await _db;
    await db.insert(
      'watch_responses',
      response.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<WatchResponse?> getById(String id) async {
    final db = await _db;
    final maps = await db.query(
      'watch_responses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return WatchResponse.fromMap(maps.first);
  }

  Future<List<WatchResponse>> getAll() async {
    final db = await _db;
    final maps = await db.query(
      'watch_responses',
      orderBy: 'timestamp DESC',
    );
    return maps.map(WatchResponse.fromMap).toList();
  }

  Future<List<WatchResponse>> getPending() async {
    final db = await _db;
    final maps = await db.query(
      'watch_responses',
      where: "sync_status = ? AND question_status = 'answered'",
      whereArgs: [SyncStatus.pending.name],
      orderBy: 'timestamp ASC',
    );
    return maps.map(WatchResponse.fromMap).toList();
  }

  Future<void> updateStatus(String id, SyncStatus status) async {
    final db = await _db;
    await db.update(
      'watch_responses',
      {'sync_status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAnswered(String id, String answerId) async {
    final db = await _db;
    await db.update(
      'watch_responses',
      {
        'question_status': QuestionStatus.answered.name,
        'answer_id': answerId,
        'sync_status': SyncStatus.pending.name,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('watch_responses');
  }
}
