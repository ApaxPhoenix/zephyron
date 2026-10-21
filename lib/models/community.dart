import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:zephyron/enums.dart';

/// A community nobody owns. Holding its key makes you a member; every member
/// can invite, post and add channels, and members are listed by seniority.
class Community {
  static const int names = 48;
  static const int abouts = 240;

  final String id;
  String name;
  String about;
  Uint8List? icon;
  Uint8List? banner;

  /// Shared secret every post is encrypted with.
  final Uint8List key;

  /// Whoever made it. They appear first among members, nothing more.
  final String founder;
  final DateTime created;
  DateTime joined;
  bool pinned;
  bool muted;

  /// Time of the description post now shown, so the newest one wins.
  int revised;

  Community({
    required this.id,
    required this.name,
    required this.key,
    required this.founder,
    this.about = '',
    this.icon,
    this.banner,
    DateTime? created,
    DateTime? joined,
    this.pinned = false,
    this.muted = false,
    this.revised = 0,
  }) : created = created ?? DateTime.now(),
       joined = joined ?? DateTime.now();

  /// The channel every community starts with.
  String get general => Community.lobby(id);

  static String lobby(String community) => sha256
      .convert(utf8.encode('zephyron/general:$community'))
      .toString()
      .substring(0, 32);

  factory Community.fromRow(Map<String, dynamic> row) {
    Uint8List? blob(Object? value) =>
        value is Uint8List && value.isNotEmpty ? value : null;
    return Community(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      about: row['about'] as String? ?? '',
      icon: blob(row['icon']),
      banner: blob(row['banner']),
      key: base64.decode(row['key'] as String),
      founder: row['founder'] as String? ?? '',
      created: DateTime.fromMillisecondsSinceEpoch(row['created'] as int? ?? 0),
      joined: DateTime.fromMillisecondsSinceEpoch(row['joined'] as int? ?? 0),
      pinned: (row['pinned'] as int? ?? 0) == 1,
      muted: (row['muted'] as int? ?? 0) == 1,
      revised: row['revised'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toRow() => {
    'id': id,
    'name': name,
    'about': about,
    'icon': icon,
    'banner': banner,
    'key': base64.encode(key),
    'founder': founder,
    'created': created.millisecondsSinceEpoch,
    'joined': joined.millisecondsSinceEpoch,
    'pinned': pinned ? 1 : 0,
    'muted': muted ? 1 : 0,
    'revised': revised,
  };
}

/// A channel inside a community.
class Room {
  final String id;
  final String community;
  String name;
  final Space kind;
  final String author;
  final DateTime created;

  Room({
    required this.id,
    required this.community,
    required this.name,
    required this.kind,
    required this.author,
    required this.created,
  });
}

/// Anything a member says or does in a community, signed and encrypted.
class Post {
  final String id;
  final String community;
  final String channel;
  final String author;

  /// Per-author counter, so members can tell exactly what they are missing.
  final int seq;
  final DateTime time;
  final Note note;
  final String text;
  final Map<String, dynamic> meta;

  /// The signed, encrypted form, relayed unchanged between members.
  final String frame;

  Post({
    required this.id,
    required this.community,
    required this.channel,
    required this.author,
    required this.seq,
    required this.time,
    required this.note,
    required this.text,
    required this.frame,
    Map<String, dynamic>? meta,
  }) : meta = meta ?? {};

  factory Post.fromRow(Map<String, dynamic> row) {
    int index(Object? value, int length) =>
        ((value as int?) ?? 0).clamp(0, length - 1);
    Map<String, dynamic> extra = {};
    final raw = row['meta'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        extra = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return Post(
      id: row['id'] as String,
      community: row['community'] as String,
      channel: row['channel'] as String? ?? '',
      author: row['author'] as String,
      seq: row['seq'] as int? ?? 0,
      time: DateTime.fromMillisecondsSinceEpoch(row['time'] as int? ?? 0),
      note: Note.values[index(row['note'], Note.values.length)],
      text: row['text'] as String? ?? '',
      meta: extra,
      frame: row['frame'] as String? ?? '',
    );
  }

  Map<String, dynamic> toRow() => {
    'id': id,
    'community': community,
    'channel': channel,
    'author': author,
    'seq': seq,
    'time': time.millisecondsSinceEpoch,
    'note': note.index,
    'text': text,
    'meta': meta.isEmpty ? null : jsonEncode(meta),
    'frame': frame,
  };
}

/// Someone in a community, as they introduced themselves when joining.
class Member {
  final String address;
  String name;
  Uint8List? avatar;
  final DateTime since;

  Member({
    required this.address,
    required this.name,
    required this.since,
    this.avatar,
  });
}
