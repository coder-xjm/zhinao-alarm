import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/alarm.dart';

/// ============================================================
/// 本地持久化层：用 SQLite 存闹钟配置
///
/// 数据库文件位于 App 私有目录，卸载即清除。
/// 重启手机、杀进程都不会丢数据。
/// ============================================================
class AlarmRepository {
  AlarmRepository._();

  static final AlarmRepository instance = AlarmRepository._();

  static const _dbName = 'zhinao_alarm.db';

  /// v1 → v2：新增「每隔 N 天」所需的 dayInterval 列
  static const _dbVersion = 2;
  static const _table = 'alarms';

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            hour INTEGER NOT NULL,
            minute INTEGER NOT NULL,
            enabled INTEGER NOT NULL,
            ruleType TEXT NOT NULL,
            weekInterval INTEGER NOT NULL,
            dayInterval INTEGER NOT NULL DEFAULT 2,
            weekdays TEXT NOT NULL,
            anchorDate INTEGER NOT NULL,
            monthDays TEXT NOT NULL,
            monthDayFallback TEXT NOT NULL,
            snoozeMinutes INTEGER NOT NULL,
            maxSnoozeTimes INTEGER NOT NULL,
            vibrate INTEGER NOT NULL,
            ringDurationSeconds INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // 老版本（v1）没有 dayInterval 列，补上。
        // 有 DEFAULT 2，老闹钟升级后不会因为缺列而读不出数据。
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN dayInterval INTEGER NOT NULL DEFAULT 2',
          );
        }
      },
    );
    return _db!;
  }

  /// 读取全部闹钟，按时间排序
  Future<List<Alarm>> loadAll() async {
    final db = await _database;
    final rows = await db.query(_table, orderBy: 'hour ASC, minute ASC');
    return rows.map(Alarm.fromMap).toList();
  }

  /// 新增或更新（按 id 覆盖）
  Future<void> upsert(Alarm alarm) async {
    final db = await _database;
    await db.insert(
      _table,
      alarm.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除
  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
