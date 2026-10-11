import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class AppDb {
  AppDb._();
  static final instance = AppDb._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'nfc_guard.db');
    return openDatabase(
      path,
      version: 7,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _addPhotoColumns(db);
        if (oldVersion < 3) await _createIncidents(db);
        if (oldVersion < 4) await _addSortOrder(db);
        if (oldVersion < 5) await _createOutbox(db);
        if (oldVersion < 6) await _addGpsColumns(db);
        if (oldVersion < 7) await _createRejected(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE checkpoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tag_id TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tag_id TEXT NOT NULL,
            checkpoint_name TEXT NOT NULL,
            guard_name TEXT NOT NULL,
            time INTEGER NOT NULL,
            known INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_logs_time ON logs(time)');
        await _addPhotoColumns(db);
        await _createIncidents(db);
        await _addSortOrder(db);
        await _createOutbox(db);
        await _addGpsColumns(db);
        await _createRejected(db);
      },
    );
  }

  /// Patrol order of checkpoints. Existing checkpoints keep their alphabetical order.
  static Future<void> _addSortOrder(Database db) async {
    await db.execute(
        'ALTER TABLE checkpoints ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
    final rows = await db.query('checkpoints',
        columns: ['id'], orderBy: 'name COLLATE NOCASE');
    for (var i = 0; i < rows.length; i++) {
      await db.update('checkpoints', {'sort_order': i},
          where: 'id = ?', whereArgs: [rows[i]['id']]);
    }
  }

  /// GPS: checkpoint positions, and where each check-in happened.
  static Future<void> _addGpsColumns(Database db) async {
    await db.execute('ALTER TABLE checkpoints ADD COLUMN lat REAL');
    await db.execute('ALTER TABLE checkpoints ADD COLUMN lng REAL');
    await db.execute('ALTER TABLE logs ADD COLUMN lat REAL');
    await db.execute('ALTER TABLE logs ADD COLUMN lng REAL');
    await db.execute('ALTER TABLE logs ADD COLUMN distance_m REAL');
    await db.execute('ALTER TABLE logs ADD COLUMN gps_status TEXT');
  }

  /// Check-ins refused by the GPS check (kept for the monthly report).
  static Future<void> _createRejected(Database db) async {
    await db.execute('''
      CREATE TABLE rejected (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time INTEGER NOT NULL,
        guard_name TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        checkpoint_name TEXT NOT NULL,
        reason TEXT NOT NULL,
        distance_m REAL,
        lat REAL,
        lng REAL
      )
    ''');
    await db.execute('CREATE INDEX idx_rejected_time ON rejected(time)');
  }

  /// Telegram messages waiting to be delivered (instant check-in notices, proof photos).
  static Future<void> _createOutbox(Database db) async {
    await db.execute('''
      CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at INTEGER NOT NULL,
        kind TEXT NOT NULL,
        text TEXT,
        path TEXT,
        targets TEXT NOT NULL,
        sent_to TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
  }

  static Future<void> _createIncidents(Database db) async {
    await db.execute('''
      CREATE TABLE incidents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time INTEGER NOT NULL,
        guard_name TEXT NOT NULL,
        category TEXT NOT NULL,
        location TEXT,
        description TEXT NOT NULL,
        media_type TEXT NOT NULL,
        video_path TEXT,
        photo_paths TEXT NOT NULL,
        voice_path TEXT,
        sent_to TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_incidents_time ON incidents(time)');
  }

  static Future<void> _addPhotoColumns(Database db) async {
    await db.execute(
        'ALTER TABLE logs ADD COLUMN photo_required INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE logs ADD COLUMN photo_path TEXT');
  }

  // ---------- 巡逻点 ----------

  Future<List<Checkpoint>> checkpoints() async {
    final rows =
        await (await db).query('checkpoints', orderBy: 'sort_order, id');
    return rows.map(Checkpoint.fromMap).toList();
  }

  /// Saves the patrol order: [ids] in the new order.
  Future<void> reorderCheckpoints(List<int> ids) async {
    await (await db).transaction((txn) async {
      for (var i = 0; i < ids.length; i++) {
        await txn.update('checkpoints', {'sort_order': i},
            where: 'id = ?', whereArgs: [ids[i]]);
      }
    });
  }

  Future<Checkpoint?> checkpointByTag(String tagId) async {
    final rows = await (await db)
        .query('checkpoints', where: 'tag_id = ?', whereArgs: [tagId]);
    return rows.isEmpty ? null : Checkpoint.fromMap(rows.first);
  }

  /// Adds a checkpoint at the end of the patrol order.
  Future<void> addCheckpoint(String tagId, String name,
      {double? lat, double? lng}) async {
    final d = await db;
    final max = Sqflite.firstIntValue(
        await d.rawQuery('SELECT MAX(sort_order) FROM checkpoints'));
    await d.insert(
      'checkpoints',
      Checkpoint(tagId: tagId, name: name, lat: lat, lng: lng).toMap()
        ..remove('id')
        ..['sort_order'] = (max ?? -1) + 1,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> setCheckpointLocation(int id, double lat, double lng) async {
    await (await db).update('checkpoints', {'lat': lat, 'lng': lng},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> renameCheckpoint(int id, String name) async {
    await (await db).update('checkpoints', {'name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCheckpoint(int id) async {
    await (await db).delete('checkpoints', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 打卡记录 ----------

  /// Inserts a log and returns its id.
  Future<int> addLog(CheckinLog log) async {
    return (await db).insert('logs', log.toMap()..remove('id'));
  }

  Future<void> setLogPhoto(int id, String path) async {
    await (await db)
        .update('logs', {'photo_path': path}, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes every check-in log and incident. Returns the number of check-in logs deleted.
  Future<int> deleteAllLogs() async {
    final d = await db;
    await d.delete('incidents');
    await d.delete('outbox');
    await d.delete('rejected');
    return d.delete('logs');
  }

  // ---------- Incidents ----------

  Future<int> addIncident(Incident i) async =>
      (await db).insert('incidents', i.toMap()..remove('id'));

  Future<Incident?> incident(int id) async {
    final rows =
        await (await db).query('incidents', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Incident.fromMap(rows.first);
  }

  Future<void> setIncidentSentTo(int id, List<String> chatIds) async {
    await (await db).update('incidents', {'sent_to': jsonEncode(chatIds)},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Incident>> incidentsBetween(DateTime from, DateTime to) async {
    final rows = await (await db).query('incidents',
        where: 'time >= ? AND time < ?',
        whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
        orderBy: 'time DESC');
    return rows.map(Incident.fromMap).toList();
  }

  Future<List<Incident>> incidentsForMonth(int year, int month) =>
      incidentsBetween(DateTime(year, month), DateTime(year, month + 1));

  Future<List<Incident>> recentIncidents({int limit = 100}) async {
    final rows =
        await (await db).query('incidents', orderBy: 'time DESC', limit: limit);
    return rows.map(Incident.fromMap).toList();
  }

  /// Incidents from the last [days] days, to retry sending to owners who haven't received them.
  Future<List<Incident>> incidentsSince(DateTime since) =>
      incidentsBetween(since, DateTime.now().add(const Duration(days: 1)));

  /// Deletes incidents before [cutoff] and returns their media paths.
  // ---------- Rejected check-ins ----------

  Future<void> addRejected(RejectedCheckin r) async =>
      (await db).insert('rejected', r.toMap()..remove('id'));

  Future<List<RejectedCheckin>> rejectedBetween(
      DateTime from, DateTime to) async {
    final rows = await (await db).query('rejected',
        where: 'time >= ? AND time < ?',
        whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
        orderBy: 'time DESC');
    return rows.map(RejectedCheckin.fromMap).toList();
  }

  Future<List<RejectedCheckin>> rejectedForMonth(int year, int month) async {
    final rows = await (await db).query('rejected',
        where: 'time >= ? AND time < ?',
        whereArgs: [
          DateTime(year, month).millisecondsSinceEpoch,
          DateTime(year, month + 1).millisecondsSinceEpoch
        ],
        orderBy: 'time DESC');
    return rows.map(RejectedCheckin.fromMap).toList();
  }

  Future<void> deleteRejectedBefore(DateTime cutoff) async =>
      (await db).delete('rejected',
          where: 'time < ?', whereArgs: [cutoff.millisecondsSinceEpoch]);

  Future<List<String>> deleteIncidentsBefore(DateTime cutoff) async {
    final d = await db;
    final ms = cutoff.millisecondsSinceEpoch;
    final rows = await d.query('incidents', where: 'time < ?', whereArgs: [ms]);
    await d.delete('incidents', where: 'time < ?', whereArgs: [ms]);
    return rows.map(Incident.fromMap).expand((i) => i.allMediaPaths).toList();
  }

  /// Deletes logs before [cutoff] and returns their photo paths (for the caller to delete).
  Future<List<String>> deleteLogsBefore(DateTime cutoff) async {
    final d = await db;
    final ms = cutoff.millisecondsSinceEpoch;
    final rows = await d.query('logs',
        columns: ['photo_path'],
        where: 'time < ? AND photo_path IS NOT NULL',
        whereArgs: [ms]);
    await d.delete('logs', where: 'time < ?', whereArgs: [ms]);
    return rows.map((r) => r['photo_path'] as String).toList();
  }

  /// [from] 含，[to] 不含
  Future<List<CheckinLog>> logsBetween(DateTime from, DateTime to) async {
    final rows = await (await db).query(
      'logs',
      where: 'time >= ? AND time < ?',
      whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'time DESC',
    );
    return rows.map(CheckinLog.fromMap).toList();
  }

  Future<List<CheckinLog>> logsForMonth(int year, int month) =>
      logsBetween(DateTime(year, month), DateTime(year, month + 1));

  Future<List<CheckinLog>> logsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    return logsBetween(start, start.add(const Duration(days: 1)));
  }

  Future<CheckinLog?> lastLogForTag(String tagId) async {
    final rows = await (await db).query(
      'logs',
      where: 'tag_id = ?',
      whereArgs: [tagId],
      orderBy: 'time DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : CheckinLog.fromMap(rows.first);
  }

  /// Most recent check-in of [tagId] by [guard].
  Future<CheckinLog?> lastLogForTagByGuard(String tagId, String guard) async {
    final rows = await (await db).query(
      'logs',
      where: 'tag_id = ? AND guard_name = ?',
      whereArgs: [tagId, guard],
      orderBy: 'time DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : CheckinLog.fromMap(rows.first);
  }

  // ---------- Outbox ----------

  Future<int> addOutbox(Map<String, Object?> row) async =>
      (await db).insert('outbox', row);

  Future<List<Map<String, Object?>>> outbox() async =>
      (await db).query('outbox', orderBy: 'id');

  Future<void> updateOutbox(int id, Map<String, Object?> values) async =>
      (await db).update('outbox', values, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteOutbox(int id) async =>
      (await db).delete('outbox', where: 'id = ?', whereArgs: [id]);

  Future<int> outboxCount() async =>
      Sqflite.firstIntValue(
          await (await db).rawQuery('SELECT COUNT(*) FROM outbox')) ??
      0;
}
