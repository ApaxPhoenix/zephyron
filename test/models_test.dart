import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/models/profile.dart';
import 'package:zephyron/services/locker.dart';
import 'package:zephyron/widgets/stamp.dart';

void main() {
  group('Message', () {
    Message make(Kind kind, {String text = '', Map<String, dynamic>? meta}) =>
        Message(
          id: 'id',
          peer: 'peer',
          mine: true,
          text: text,
          kind: kind,
          meta: meta,
          time: DateTime(2026, 3, 4, 5, 6),
          status: Status.delivered,
        );

    test('rows round trip with metadata', () {
      final original = make(
        Kind.image,
        text: 'caption',
        meta: {'name': 'a.png', 'width': 10, 'height': 20, 'size': 30},
      );
      final copy = Message.fromRow(original.toRow());
      expect(copy.kind, Kind.image);
      expect(copy.text, 'caption');
      expect(copy.width, 10);
      expect(copy.height, 20);
      expect(copy.status, Status.delivered);
      expect(copy.time, original.time);
    });

    test('previews describe every kind', () {
      expect(
        make(Kind.text, text: 'line one\nline two').preview,
        'line one line two',
      );
      expect(make(Kind.image).preview, 'Photo');
      expect(make(Kind.image, text: 'beach').preview, 'beach');
      expect(make(Kind.gif).preview, 'GIF');
      expect(make(Kind.file, meta: {'name': 'cv.pdf'}).preview, 'cv.pdf');
      expect(make(Kind.card, meta: {'name': 'Maya'}).preview, 'Trustee · Maya');
    });

    test('media flags', () {
      expect(make(Kind.gif).media, isTrue);
      expect(make(Kind.file).attachment, isTrue);
      expect(make(Kind.card).attachment, isFalse);
    });

    test('corrupt rows fall back safely', () {
      final copy = Message.fromRow({
        'id': 'x',
        'peer': 'y',
        'kind': 99,
        'status': -4,
        'meta': '{not json',
      });
      expect(copy.kind, Kind.text);
      expect(copy.status, Status.sending);
      expect(copy.meta, isEmpty);
    });
  });

  test('sizes are human readable', () {
    expect(measure(512), '512 B');
    expect(measure(2048), '2 KB');
    expect(measure(5 * 1024 * 1024), '5.0 MB');
  });

  test('mime types follow the extension', () {
    expect(Locker.mime('photo.JPG'), 'image/jpeg');
    expect(Locker.mime('anim.gif'), 'image/gif');
    expect(Locker.mime('doc.pdf'), 'application/pdf');
    expect(Locker.mime('archive'), 'application/octet-stream');
  });

  test('preferences fall back to defaults for unknown values', () {
    final prefs = Preferences.fromJson({'theme': 'neon', 'rating': 'x'});
    expect(prefs.theme, ThemeMode.system);
    expect(prefs.rating, Rating.pg);
    expect(prefs.receipts, isTrue);
  });

  group('Stamps', () {
    final now = DateTime.now();

    test('clock pads hours and minutes', () {
      expect(clock(DateTime(2026, 1, 1, 7, 5)), '07:05');
    });

    test('brief and heading read naturally', () {
      expect(brief(now), clock(now));
      expect(brief(now.subtract(const Duration(days: 1))), 'Yesterday');
      expect(heading(now), 'Today');
      expect(heading(now.subtract(const Duration(days: 1))), 'Yesterday');
      expect(heading(DateTime(2001, 2, 3)), contains('2001'));
    });

    test('ago rounds to the nearest unit', () {
      expect(ago(now), 'just now');
      expect(ago(now.subtract(const Duration(minutes: 5))), '5 min ago');
      expect(ago(now.subtract(const Duration(hours: 3))), '3 h ago');
    });
  });
}
