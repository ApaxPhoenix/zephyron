import 'dart:typed_data';
import 'package:zephyron/enums.dart';

class Trustee {
  final String address;
  String nickname;
  Trust trust;
  bool pinned;
  bool archived;
  DateTime created;

  String alias;
  String biography;
  String mood;
  Availability availability;
  Uint8List? avatar;
  Uint8List? banner;

  /// Who holds messages for them while they are offline, from their profile.
  String mailbox;
  int revision;

  /// Seconds until messages in this chat disappear, or 0 to keep them.
  int fuse;

  /// When the timer last changed, so the newer choice wins on both sides.
  int fused;

  Trustee({
    required this.address,
    this.nickname = '',
    this.trust = Trust.trustee,
    this.pinned = false,
    this.archived = false,
    DateTime? created,
    this.alias = '',
    this.biography = '',
    this.mood = '',
    this.availability = Availability.available,
    this.avatar,
    this.banner,
    this.mailbox = '',
    this.revision = 0,
    this.fuse = 0,
    this.fused = 0,
  }) : created = created ?? DateTime.now();

  factory Trustee.from(Map<String, dynamic> row) {
    final picture = row['avatar'];
    final cover = row['banner'];
    return Trustee(
      address: row['address'] as String,
      nickname: row['nickname'] as String? ?? '',
      trust:
          Trust.values[((((row['trust']) as int?) ?? 0).clamp(
            0,
            Trust.values.length - 1,
          ))],
      pinned: (row['pinned'] as int? ?? 0) == 1,
      archived: (row['archived'] as int? ?? 0) == 1,
      created: DateTime.fromMillisecondsSinceEpoch(row['created'] as int? ?? 0),
      alias: row['alias'] as String? ?? '',
      biography: row['bio'] as String? ?? '',
      mood: row['mood'] as String? ?? '',
      availability:
          Availability.values[((((row['availability']) as int?) ?? 0).clamp(
            0,
            Availability.values.length - 1,
          ))],
      avatar: picture is Uint8List && picture.isNotEmpty ? picture : null,
      banner: cover is Uint8List && cover.isNotEmpty ? cover : null,
      mailbox: row['mailbox'] as String? ?? '',
      revision: row['revision'] as int? ?? 0,
      fuse: row['fuse'] as int? ?? 0,
      fused: row['fused'] as int? ?? 0,
    );
  }

  Map<String, dynamic> row() {
    return {
      'address': address,
      'nickname': nickname,
      'trust': trust.index,
      'pinned': pinned ? 1 : 0,
      'archived': archived ? 1 : 0,
      'created': created.millisecondsSinceEpoch,
      'alias': alias,
      'bio': biography,
      'mood': mood,
      'availability': availability.index,
      'avatar': avatar,
      'banner': banner,
      'mailbox': mailbox,
      'revision': revision,
      'fuse': fuse,
      'fused': fused,
    };
  }

  String get label {
    if (nickname.trim().isNotEmpty) return nickname.trim();
    if (alias.trim().isNotEmpty) return alias.trim();
    return short;
  }

  String get short => address.length > 10 ? address.substring(0, 10) : address;

  bool get trusted => trust == Trust.trustee;

  bool get stranger => trust == Trust.stranger;

  bool get blocked => trust == Trust.blocked;
}
