import 'dart:convert';
import 'package:zephyron/enums.dart';

class Message {
  final String id;
  final String peer;
  final bool mine;
  final Kind kind;
  final String text;
  final DateTime time;
  final Map<String, dynamic> meta;
  Status status;

  Message({
    required this.id,
    required this.peer,
    required this.mine,
    required this.text,
    required this.time,
    this.kind = Kind.text,
    Map<String, dynamic>? meta,
    this.status = Status.sending,
  }) : meta = meta ?? <String, dynamic>{};

  factory Message.fromRow(Map<String, dynamic> row) {
    int index(Object? value, int length) =>
        ((value as int?) ?? 0).clamp(0, length - 1);

    Map<String, dynamic> extra = {};
    final raw = row['meta'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        extra = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }

    return Message(
      id: row['id'] as String,
      peer: row['peer'] as String,
      mine: (row['mine'] as int? ?? 0) == 1,
      // An unknown kind is shown as text rather than as some other card.
      kind: (row['kind'] as int? ?? 0) < Kind.values.length
          ? Kind.values[index(row['kind'], Kind.values.length)]
          : Kind.text,
      text: row['text'] as String? ?? '',
      time: DateTime.fromMillisecondsSinceEpoch(row['time'] as int? ?? 0),
      meta: extra,
      status: Status.values[index(row['status'], Status.values.length)],
    );
  }

  Map<String, dynamic> toRow() {
    return {
      'id': id,
      'peer': peer,
      'mine': mine ? 1 : 0,
      'kind': kind.index,
      'text': text,
      'time': time.millisecondsSinceEpoch,
      'meta': meta.isEmpty ? null : jsonEncode(meta),
      'status': status.index,
    };
  }

  bool get media => kind == Kind.image || kind == Kind.gif;

  bool get attachment =>
      media || kind == Kind.file || kind == Kind.voice || kind == Kind.video;

  /// Length of a voice message or video.
  Duration get duration =>
      Duration(milliseconds: meta['duration'] as int? ?? 0);

  String get name => meta['name'] as String? ?? 'file';

  String get mime => meta['mime'] as String? ?? 'application/octet-stream';

  int get size => meta['size'] as int? ?? 0;

  int get width => meta['width'] as int? ?? 0;

  int get height => meta['height'] as int? ?? 0;

  /// Seconds this message lives for, or 0 when it is kept.
  int get fuse => meta['fuse'] as int? ?? 0;

  DateTime? get expiry => fuse > 0 ? time.add(Duration(seconds: fuse)) : null;

  String get preview {
    final caption = text.replaceAll('\n', ' ').trim();
    return switch (kind) {
      Kind.text => caption,
      Kind.image => caption.isEmpty ? 'Photo' : caption,
      Kind.gif => 'GIF',
      Kind.file => name,
      Kind.card => 'Trustee · ${meta['name'] ?? 'card'}',
      Kind.invite => 'Invitation · ${meta['name'] ?? 'community'}',
      Kind.voice => 'Voice message · ${length(duration)}',
      Kind.video => caption.isEmpty ? 'Video · ${length(duration)}' : caption,
    };
  }
}

/// A duration as minutes and seconds, like 1:07.
String length(Duration duration) {
  final seconds = duration.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String measure(int size) {
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
  return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
}
