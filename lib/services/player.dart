import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays a voice message, an episode or a video with the phone's own media
/// player, through a small channel: MediaPlayer on Android and AVPlayer on
/// iOS. A video draws into a texture shown with Flutter's [Texture].
class Player extends ChangeNotifier {
  static const MethodChannel link = MethodChannel('zephyron/player');
  static final Map<int, Player> live = {};
  static int counter = 0;
  static bool listening = false;

  final int id;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  bool playing = false;
  bool closed = false;

  /// The texture a video draws into, and its size as stored.
  int? texture;
  int width = 0;
  int height = 0;

  /// Degrees the picture still has to be turned to stand upright.
  int rotation = 0;
  Timer? ticker;

  Player._(this.id);

  /// Width over height, as the picture is meant to be seen.
  double get aspect {
    if (width <= 0 || height <= 0) return 16 / 9;
    final ratio = width / height;
    return rotation % 180 == 0 ? ratio : 1 / ratio;
  }

  static void listen() {
    if (listening) return;
    listening = true;
    link.setMethodCallHandler((call) async {
      if (call.method != 'done') return;
      live[(call.arguments as Map)['id']]?.finish();
    });
  }

  /// Opens [path]; a [video] gets a texture to draw into.
  static Future<Player> open(String path, {bool video = false}) async {
    listen();
    final player = Player._(counter++);
    live[player.id] = player;
    try {
      final facts = await link.invokeMapMethod<String, Object?>('open', {
        'id': player.id,
        'path': path,
        'video': video,
      });
      player
        ..duration = Duration(
          milliseconds: (facts?['duration'] as num?)?.toInt() ?? 0,
        )
        ..width = (facts?['width'] as num?)?.toInt() ?? 0
        ..height = (facts?['height'] as num?)?.toInt() ?? 0
        ..rotation = (facts?['rotation'] as num?)?.toInt() ?? 0
        ..texture = (facts?['texture'] as num?)?.toInt();
      return player;
    } catch (_) {
      live.remove(player.id);
      rethrow;
    }
  }

  Future<void> play() async {
    if (closed) return;
    await link.invokeMethod<void>('play', {'id': id});
    playing = true;
    ticker ??= Timer.periodic(const Duration(milliseconds: 200), (_) => poll());
    notifyListeners();
  }

  Future<void> pause() async {
    if (closed) return;
    await link.invokeMethod<void>('pause', {'id': id});
    playing = false;
    ticker?.cancel();
    ticker = null;
    await poll();
  }

  Future<void> seek(Duration to) async {
    if (closed) return;
    await link.invokeMethod<void>('seek', {'id': id, 'at': to.inMilliseconds});
    position = to;
    notifyListeners();
  }

  Future<void> poll() async {
    if (closed) return;
    final at = await link.invokeMethod<int>('position', {'id': id});
    if (at == null || closed) return;
    position = Duration(milliseconds: at);
    notifyListeners();
  }

  /// Played to the end.
  void finish() {
    playing = false;
    ticker?.cancel();
    ticker = null;
    position = Duration.zero;
    notifyListeners();
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    ticker?.cancel();
    ticker = null;
    live.remove(id);
    dispose();
    try {
      await link.invokeMethod<void>('close', {'id': id});
    } catch (_) {}
  }
}
