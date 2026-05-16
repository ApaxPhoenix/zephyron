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
  int revision;

  Profile({
    this.name = '',
    this.bio = '',
    this.mood = '',
    this.availability = Availability.available,
    this.avatar,
    this.revision = 0,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final picture = json['avatar'] as String?;
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
      revision: json['revision'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'bio': bio,
      'mood': mood,
      'availability': availability.name,
      'avatar': avatar == null ? '' : base64.encode(avatar!),
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
  ThemeMode theme;
  Rating rating;

  Preferences({
    this.receipts = true,
    this.typing = true,
    this.strangers = true,
    this.banners = true,
    this.haptics = true,
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
      'theme': theme.name,
      'rating': rating.name,
    };
  }
}
