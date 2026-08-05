import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:zephyron/enums.dart';

class Profile {
  static const int names = 32;
  static const int bios = 160;
  static const int moods = 80;

  String name;
  String bio;
  String mood;
  Availability availability;
  Uint8List? avatar;

  /// A wide picture or animated GIF shown behind the avatar.
  Uint8List? banner;

  /// The trustee that holds messages for this identity while it is
  /// offline, often a spare phone of their own, or empty.
  String mailbox;
  int revision;

  Profile({
    this.name = '',
    this.bio = '',
    this.mood = '',
    this.availability = Availability.available,
    this.avatar,
    this.banner,
    this.mailbox = '',
    this.revision = 0,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final picture = json['avatar'] as String?;
    final cover = json['banner'] as String?;
    final state = json['availability'] as String?;
    return Profile(
      name: clip(json['name'], names),
      bio: clip(json['bio'], bios),
      mood: clip(json['mood'], moods),
      availability: Availability.values.firstWhere(
        (item) => item.name == state,
        orElse: () => Availability.available,
      ),
      avatar: picture != null && picture.isNotEmpty
          ? base64.decode(picture)
          : null,
      banner: cover != null && cover.isNotEmpty ? base64.decode(cover) : null,
      mailbox: clip(json['mailbox'], 62).toLowerCase(),
      revision: json['revision'] as int? ?? 0,
    );
  }

  /// The banner is left out of frames sent to trustees, which carry it in a
  /// frame of its own; it is kept when the profile is stored locally.
  Map<String, dynamic> toJson({bool banner = true}) {
    return {
      'name': name,
      'bio': bio,
      'mood': mood,
      'availability': availability.name,
      'avatar': avatar == null ? '' : base64.encode(avatar!),
      if (banner)
        'banner': this.banner == null ? '' : base64.encode(this.banner!),
      'mailbox': mailbox,
      'revision': revision,
    };
  }

  Profile copy() => Profile.fromJson(toJson());

  static String clip(Object? value, int limit) {
    final text = (value is String ? value : '').trim();
    return text.length > limit ? text.substring(0, limit) : text;
  }
}

class Preferences {
  bool receipts;
  bool typing;
  bool strangers;
  bool banners;
  bool haptics;

  /// Blocks screenshots and hides the app in the app switcher.
  bool shield;

  /// Holds sealed messages for trustees while the person they are for is
  /// offline.
  bool carry;

  /// The trustee this phone is a mailbox for, or empty.
  String serve;

  /// Lists this identity in the directory, so people it has not met can
  /// find it and send a request.
  bool listed;

  /// Passes the directory listings this phone holds on to trustees.
  bool spread;
  ThemeMode theme;
  Rating rating;

  Preferences({
    this.receipts = true,
    this.typing = true,
    this.strangers = true,
    this.banners = true,
    this.haptics = true,
    this.shield = true,
    this.carry = true,
    this.serve = '',
    this.listed = false,
    this.spread = true,
    this.theme = ThemeMode.system,
    this.rating = Rating.pg,
  });

  factory Preferences.fromJson(Map<String, dynamic> json) {
    return Preferences(
      receipts: json['receipts'] as bool? ?? true,
      typing: json['typing'] as bool? ?? true,
      strangers: json['strangers'] as bool? ?? true,
      banners: json['banners'] as bool? ?? true,
      haptics: json['haptics'] as bool? ?? true,
      shield: json['shield'] as bool? ?? true,
      carry: json['carry'] as bool? ?? true,
      serve: json['serve'] as String? ?? '',
      listed: json['listed'] as bool? ?? false,
      spread: json['spread'] as bool? ?? true,
      theme: ThemeMode.values.firstWhere(
        (item) => item.name == json['theme'],
        orElse: () => ThemeMode.system,
      ),
      rating: Rating.values.firstWhere(
        (item) => item.name == json['rating'],
        orElse: () => Rating.pg,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'receipts': receipts,
      'typing': typing,
      'strangers': strangers,
      'banners': banners,
      'haptics': haptics,
      'shield': shield,
      'carry': carry,
      'serve': serve,
      'listed': listed,
      'spread': spread,
      'theme': theme.name,
      'rating': rating.name,
    };
  }
}
