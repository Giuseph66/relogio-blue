import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../../core/logger/app_logger.dart';

/// Singleton SQLite database for the app.
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _db;

  static const _dbName = 'relogio.db';
  static const _dbVersion = 2;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);
    AppLogger.info('AppDatabase: opening at $fullPath');

    return openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE watch_responses (
        id               TEXT PRIMARY KEY,
        location_id      TEXT NOT NULL,
        location_name    TEXT NOT NULL,
        question_id      TEXT NOT NULL,
        answer_id        TEXT NOT NULL DEFAULT '',
        timestamp        TEXT NOT NULL,
        sync_status      TEXT NOT NULL DEFAULT 'pending',
        question_status  TEXT NOT NULL DEFAULT 'answered',
        question_command TEXT NOT NULL DEFAULT ''
      )
    ''');
    AppLogger.info('AppDatabase: created tables (v$version)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    AppLogger.info('AppDatabase: upgrade $oldVersion → $newVersion');
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE watch_responses ADD COLUMN question_status TEXT NOT NULL DEFAULT 'answered'",
      );
      await db.execute(
        "ALTER TABLE watch_responses ADD COLUMN question_command TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  /// Close the database (mainly for tests).
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
