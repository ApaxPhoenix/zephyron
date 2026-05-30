import 'dart:convert';
import 'dart:developer' as developer;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/trustee.dart';
import 'package:zephyron/sql/database.dart';

class Ledger {
  static cipher.Database get base {
    final instance = Database.databaseInstance;
    if (instance == null || !instance.isOpen) {
      throw StateError('Identity store is locked');
    }
    return instance;
  }

  static Future<void> ensure() async {
    try {
      await base.execute('''
        CREATE TABLE IF NOT EXISTS trustees (
          address TEXT PRIMARY KEY,
          nickname TEXT NOT NULL DEFAULT '',
          trust INTEGER NOT NULL DEFAULT 1,
          pinned INTEGER NOT NULL DEFAULT 0,
          archived INTEGER NOT NULL DEFAULT 0,
          created INTEGER NOT NULL,
          alias TEXT NOT NULL DEFAULT '',
          bio TEXT NOT NULL DEFAULT '',
          mood TEXT NOT NULL DEFAULT '',
          availability INTEGER NOT NULL DEFAULT 0,
          avatar BLOB,
          banner BLOB,
          revision INTEGER NOT NULL DEFAULT 0,
          fuse INTEGER NOT NULL DEFAULT 0,
          fused INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await base.execute('''
        CREATE TABLE IF NOT EXISTS history (
          id TEXT PRIMARY KEY,
          peer TEXT NOT NULL,
          mine INTEGER NOT NULL,
          kind INTEGER NOT NULL DEFAULT 0,
          text TEXT NOT NULL,
          time INTEGER NOT NULL,
          meta TEXT,
          status INTEGER NOT NULL
        )
      ''');
      await base.execute(
        'CREATE INDEX IF NOT EXISTS history_peer ON history (peer, time)',
      );
      await base.execute('''
        CREATE TABLE IF NOT EXISTS communities (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          about TEXT NOT NULL DEFAULT '',
          icon BLOB,
          banner BLOB,
          key TEXT NOT NULL,
          founder TEXT NOT NULL,
          created INTEGER NOT NULL,
          joined INTEGER NOT NULL,
          pinned INTEGER NOT NULL DEFAULT 0,
          muted INTEGER NOT NULL DEFAULT 0,
          revised INTEGER NOT NULL DEFAULT 0,
          keys TEXT,
          epoch TEXT,
          rotated INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await base.execute('''
        CREATE TABLE IF NOT EXISTS posts (
          id TEXT PRIMARY KEY,
          community TEXT NOT NULL,
          channel TEXT NOT NULL,
          author TEXT NOT NULL,
          seq INTEGER NOT NULL,
          time INTEGER NOT NULL,
          note INTEGER NOT NULL,
          text TEXT NOT NULL,
          meta TEXT,
          frame TEXT NOT NULL
        )
      ''');
      await base.execute(
        'CREATE INDEX IF NOT EXISTS posts_community ON posts (community, time)',
      );
      await base.execute('''
        CREATE TABLE IF NOT EXISTS preferences (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      for (final (table, name, type) in [
        ('history', 'kind', 'INTEGER NOT NULL DEFAULT 0'),
        ('history', 'meta', 'TEXT'),
        ('trustees', 'fuse', 'INTEGER NOT NULL DEFAULT 0'),
        ('trustees', 'fused', 'INTEGER NOT NULL DEFAULT 0'),
        ('trustees', 'banner', 'BLOB'),
        ('communities', 'keys', 'TEXT'),
        ('communities', 'epoch', 'TEXT'),
        ('communities', 'rotated', 'INTEGER NOT NULL DEFAULT 0'),
      ]) {
        final columns = await base.rawQuery('PRAGMA table_info($table)');
        if (!columns.any((row) => row['name'] == name)) {
          await base.execute('ALTER TABLE $table ADD COLUMN $name $type');
        }
      }

      final legacy = await base.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'contacts'",
      );
      if (legacy.isNotEmpty) {
        await base.transaction((batch) async {
          await batch.execute('''
            INSERT OR IGNORE INTO trustees (address, nickname, trust, pinned, archived, created)
            SELECT address, name, CASE pending WHEN 1 THEN 0 ELSE 1 END, pinned, archived, created
            FROM contacts
          ''');
          await batch.execute('DROP TABLE contacts');
        });
        developer.log(
          'Migrated legacy contacts into the trustees table',
          name: 'Ledger.ensure',
          level: 800,
        );
      }
    } catch (error) {
      developer.log(
        'Failed to provision trustee, history and preference tables',
        name: 'Ledger.ensure',
        level: 1000,
        error: error,
        stackTrace: StackTrace.current,
      );
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> read(String key) async {
    final rows = await base.query(
      'preferences',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(
      jsonDecode(rows.first['value'] as String) as Map,
    );
  }

  static Future<void> write(String key, Map<String, dynamic> value) async {
    await base.insert('preferences', {
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: cipher.ConflictAlgorithm.replace);
  }

  static Future<void> remove(String key) async {
    await base.delete('preferences', where: 'key = ?', whereArgs: [key]);
  }

  static Future<List<Community>> communities() async {
    final rows = await base.query('communities');
    return rows.map(Community.fromRow).toList();
  }

  static Future<void> gather(Community community) async {
    await base.insert(
      'communities',
      community.toRow(),
      conflictAlgorithm: cipher.ConflictAlgorithm.replace,
    );
  }

  static Future<void> disband(String id) async {
    await base.transaction((batch) async {
      await batch.delete('posts', where: 'community = ?', whereArgs: [id]);
      await batch.delete('communities', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<List<Post>> posts() async {
    final rows = await base.query('posts', orderBy: 'time ASC');
    return rows.map(Post.fromRow).toList();
  }

  static Future<bool> publish(Post post) async {
    final row = await base.insert(
      'posts',
      post.toRow(),
      conflictAlgorithm: cipher.ConflictAlgorithm.ignore,
    );
    return row != 0;
  }

  static Future<List<Trustee>> trustees() async {
    final rows = await base.query('trustees');
    return rows.map(Trustee.fromRow).toList();
  }

  static Future<void> keep(Trustee trustee) async {
    await base.insert(
      'trustees',
      trustee.toRow(),
      conflictAlgorithm: cipher.ConflictAlgorithm.replace,
    );
  }

  static Future<void> forget(String address) async {
    await base.transaction((batch) async {
      await batch.delete('history', where: 'peer = ?', whereArgs: [address]);
      await batch.delete(
        'trustees',
        where: 'address = ?',
        whereArgs: [address],
      );
    });
  }

  static Future<void> clear(String address) async {
    await base.delete('history', where: 'peer = ?', whereArgs: [address]);
  }

  static Future<List<Message>> everything() async {
    final rows = await base.query('history', orderBy: 'time ASC');
    return rows.map(Message.fromRow).toList();
  }

  static Future<bool> record(Message message) async {
    final row = await base.insert(
      'history',
      message.toRow(),
      conflictAlgorithm: cipher.ConflictAlgorithm.ignore,
    );
    return row != 0;
  }

  static Future<bool> exists(String id) async {
    final rows = await base.query(
      'history',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<void> mark(String id, Status status) async {
    await base.update(
      'history',
      {'status': status.index},
      where: 'id = ? AND status < ?',
      whereArgs: [id, status.index],
    );
  }

  static Future<void> erase(String id) async {
    await base.delete('history', where: 'id = ?', whereArgs: [id]);
  }
}
