import 'dart:convert';
import 'dart:developer' as developer;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/community.dart';
import 'package:zephyron/models/identity.dart';
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
          mailbox TEXT NOT NULL DEFAULT '',
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
          rotated INTEGER NOT NULL DEFAULT 0,
          grouped INTEGER NOT NULL DEFAULT 0,
          listed INTEGER NOT NULL DEFAULT 0
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
        CREATE TABLE IF NOT EXISTS parcels (
          id TEXT PRIMARY KEY,
          sender TEXT NOT NULL,
          recipient TEXT NOT NULL,
          frame TEXT NOT NULL,
          time INTEGER NOT NULL
        )
      ''');
      await base.execute('''
        CREATE TABLE IF NOT EXISTS listings (
          id TEXT PRIMARY KEY,
          frame TEXT NOT NULL,
          time INTEGER NOT NULL
        )
      ''');
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
        ('trustees', 'mailbox', "TEXT NOT NULL DEFAULT ''"),
        ('communities', 'keys', 'TEXT'),
        ('communities', 'epoch', 'TEXT'),
        ('communities', 'rotated', 'INTEGER NOT NULL DEFAULT 0'),
        ('communities', 'grouped', 'INTEGER NOT NULL DEFAULT 0'),
        ('communities', 'listed', 'INTEGER NOT NULL DEFAULT 0'),
      ]) {
        final columns = await base.rawQuery('PRAGMA table_info($table)');
        if (!columns.any((row) => row['name'] == name)) {
          await base.execute('ALTER TABLE $table ADD COLUMN $name $type');
        }
      }

      await mend();

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

  /// Rewrites addresses saved by builds whose onion checksum used SHA-256,
  /// which Tor refuses, to the real address of the same key. Sessions,
  /// parcels and listings made under the old addresses are dropped and are
  /// made again on the next contact. Runs once per identity.
  static Future<void> mend() async {
    final done = await base.query(
      'preferences',
      where: 'key = ?',
      whereArgs: ['mended'],
      limit: 1,
    );
    if (done.isNotEmpty) return;
    await base.transaction((batch) async {
      for (final row in await batch.query('trustees', columns: ['address'])) {
        final old = row['address'] as String;
        final fresh = Identity.mend(old);
        if (fresh == old) continue;
        final taken = await batch.query(
          'trustees',
          where: 'address = ?',
          whereArgs: [fresh],
          limit: 1,
        );
        if (taken.isEmpty) {
          await batch.update(
            'trustees',
            {'address': fresh},
            where: 'address = ?',
            whereArgs: [old],
          );
        } else {
          await batch.delete(
            'trustees',
            where: 'address = ?',
            whereArgs: [old],
          );
        }
      }
      for (final (table, column) in [
        ('history', 'peer'),
        ('communities', 'founder'),
        ('posts', 'author'),
      ]) {
        final rows = await batch.rawQuery(
          'SELECT DISTINCT $column FROM $table',
        );
        for (final row in rows) {
          final old = row[column] as String;
          final fresh = Identity.mend(old);
          if (fresh == old) continue;
          await batch.update(
            table,
            {column: fresh},
            where: '$column = ?',
            whereArgs: [old],
          );
        }
      }
      await batch.delete('parcels');
      await batch.delete('listings');
      for (final row in await batch.query('preferences')) {
        final key = row['key'] as String;
        final value = row['value'] as String;
        if (key.startsWith('ratchet:') ||
            key.startsWith('bundle:') ||
            key.startsWith('prekeys:')) {
          await batch.delete('preferences', where: 'key = ?', whereArgs: [key]);
          continue;
        }
        final fresh = (value.replaceAllMapped(
          RegExp(r'[a-z2-7]{56}\.onion'),
          (match) => Identity.mend(match.group(0)!),
        ));
        if (fresh != value) {
          await batch.update(
            'preferences',
            {'value': fresh},
            where: 'key = ?',
            whereArgs: [key],
          );
        }
      }
      await batch.insert('preferences', {
        'key': 'mended',
        'value': '{}',
      }, conflictAlgorithm: cipher.ConflictAlgorithm.replace);
    });
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
    return rows.map(Community.from).toList();
  }

  static Future<void> gather(Community community) async {
    await base.insert(
      'communities',
      community.row(),
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
    return rows.map(Post.from).toList();
  }

  static Future<bool> publish(Post post) async {
    final row = await base.insert(
      'posts',
      post.row(),
      conflictAlgorithm: cipher.ConflictAlgorithm.ignore,
    );
    return row != 0;
  }

  /// Holds a parcel for [recipient], unless [sender] already has [share]
  /// waiting or this phone is carrying [total] in all.
  static Future<bool> hold({
    required String id,
    required String sender,
    required String recipient,
    required String frame,
    int share = 200,
    int total = 2000,
  }) async {
    int count(List<Map<String, Object?>> rows) =>
        rows.first.values.first as int;
    final mine = count(
      await base.rawQuery('SELECT COUNT(*) FROM parcels WHERE sender = ?', [
        sender,
      ]),
    );
    final all = count(await base.rawQuery('SELECT COUNT(*) FROM parcels'));
    if (mine >= share || all >= total) return false;
    await base.insert('parcels', {
      'id': id,
      'sender': sender,
      'recipient': recipient,
      'frame': frame,
      'time': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: cipher.ConflictAlgorithm.ignore);
    return true;
  }

  static Future<List<Map<String, Object?>>> parcels({String? recipient}) =>
      recipient == null
      ? base.query('parcels', orderBy: 'time ASC')
      : base.query(
          'parcels',
          where: 'recipient = ?',
          whereArgs: [recipient],
          orderBy: 'time ASC',
        );

  static Future<void> handed(String id) async {
    await base.delete('parcels', where: 'id = ?', whereArgs: [id]);
  }

  /// Forgets what [table], parcels or listings, has kept since before
  /// [before].
  static Future<void> prune(String table, DateTime before) async {
    await base.delete(
      table,
      where: 'time < ?',
      whereArgs: [before.millisecondsSinceEpoch],
    );
  }

  /// Every directory listing held, as the frames they arrived in.
  static Future<List<String>> listings() async {
    final rows = await base.query('listings', columns: ['frame']);
    return [for (final row in rows) row['frame'] as String];
  }

  static Future<void> list(String id, String frame, int time) async {
    await base.insert('listings', {
      'id': id,
      'frame': frame,
      'time': time,
    }, conflictAlgorithm: cipher.ConflictAlgorithm.replace);
  }

  static Future<void> unlist(String id) async {
    await base.delete('listings', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Trustee>> trustees() async {
    final rows = await base.query('trustees');
    return rows.map(Trustee.from).toList();
  }

  static Future<void> keep(Trustee trustee) async {
    await base.insert(
      'trustees',
      trustee.row(),
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
    return rows.map(Message.from).toList();
  }

  static Future<bool> record(Message message) async {
    final row = await base.insert(
      'history',
      message.row(),
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
