import 'dart:typed_data';
import 'package:zephyron/enums.dart';

/// An entry in the directory: someone, or a community, that asked to be
/// found. Signed by its author and passed between phones exactly as written.
class Listing {
  final Shelf shelf;

  /// The person's discovery key, or the community's id.
  final String subject;

  /// Who signed it: the person themselves, or the community's founder.
  final String author;
  final String name;
  final String about;
  final Uint8List? picture;

  /// How many members the founder counted when listing a community.
  final int members;

  /// The keys a community listing hands to anyone who joins.
  final Map<String, dynamic> invitation;
  final DateTime time;

  /// Taken down by its author. Kept until it expires so that older copies
  /// still passing between phones lose to it.
  final bool gone;

  /// The signed frame, passed along unchanged.
  final Map<String, dynamic> frame;

  const Listing({
    required this.shelf,
    required this.subject,
    required this.author,
    required this.time,
    required this.frame,
    this.name = '',
    this.about = '',
    this.picture,
    this.members = 0,
    this.invitation = const {},
    this.gone = false,
  });

  /// One per author and subject; a newer listing replaces an older one.
  String get id => key(shelf, subject, author);

  static String key(Shelf shelf, String subject, String author) =>
      '${shelf.name}:$subject:$author';
}
