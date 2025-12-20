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
  String bio;
  String mood;
  Availability availability;
  Uint8List? avatar;
  int revision;

  Trustee({
    required this.address,
    this.nickname = '',
    this.trust = Trust.trustee,
    this.pinned = false,
    this.archived = false,
    DateTime? created,
    this.alias = '',
    this.bio = '',
    this.mood = '',
    this.availability = Availability.available,
    this.avatar,
    this.revision = 0,
  }) : created = created ?? DateTime.now();

  factory Trustee.fromRow(Map<String, dynamic> row) {
    int index(Object? value, int length) =>
        ((value as int?) ?? 0).clamp(0, length - 1);

    final picture = row['avatar'];
    return Trustee(
      address: row['address'] as String,
      nickname: row['nickname'] as String? ?? '',
      trust: Trust.values[index(row['trust'], Trust.values.length)],
      pinned: (row['pinned'] as int? ?? 0) == 1,
      archived: (row['archived'] as int? ?? 0) == 1,
      created: DateTime.fromMillisecondsSinceEpoch(row['created'] as int? ?? 0),
      alias: row['alias'] as String? ?? '',
      bio: row['bio'] as String? ?? '',
      mood: row['mood'] as String? ?? '',
      availability: Availability
          .values[index(row['availability'], Availability.values.length)],
      avatar: picture is Uint8List && picture.isNotEmpty ? picture : null,
      revision: row['revision'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toRow() {
    return {
      'address': address,
      'nickname': nickname,
      'trust': trust.index,
      'pinned': pinned ? 1 : 0,
      'archived': archived ? 1 : 0,
      'created': created.millisecondsSinceEpoch,
      'alias': alias,
      'bio': bio,
      'mood': mood,
      'availability': availability.index,
      'avatar': avatar,
      'revision': revision,
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
