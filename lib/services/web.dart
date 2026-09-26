import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:zephyron/enums.dart';
import 'package:zephyron/wrappers/tor.dart';

class Web {
  static final HttpClient client = HttpClient()
    ..findProxy = ((_) => 'PROXY 127.0.0.1:${Tor.tunnel}')
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(seconds: 20)
    ..userAgent = 'Mozilla/5.0';

  static final LinkedHashMap<String, Uint8List> memory = LinkedHashMap();
  static int held = 0;
  static const int budget = 24 * 1024 * 1024;

  static Future<Uint8List> fetch(Uri uri, {int limit = 8 * 1024 * 1024}) async {
    final key = uri.toString();
    final hit = memory.remove(key);
    if (hit != null) {
      memory[key] = hit;
      return hit;
    }

    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 45))) {
      builder.add(chunk);
      if (builder.length > limit) {
        throw HttpException('Response larger than $limit bytes', uri: uri);
      }
    }
    final bytes = builder.takeBytes();

    memory[key] = bytes;
    held += bytes.length;
    while (held > budget && memory.isNotEmpty) {
      held -= memory.remove(memory.keys.first)!.length;
    }
    return bytes;
  }
}

class Gif {
  final String id;
  final String title;
  final Uri preview;
  final Uri full;
  final int width;
  final int height;

  const Gif({
    required this.id,
    required this.title,
    required this.preview,
    required this.full,
    required this.width,
    required this.height,
  });
}

class Giphy {
  static const String key = String.fromEnvironment('GIPHY_API_KEY');
  static const int page = 24;

  static bool get ready => key.isNotEmpty;

  static Future<List<Gif>> query(String text, int offset, Rating rating) async {
    if (!ready) throw StateError('GIPHY_API_KEY is not configured');
    final uri = Uri.https(
      'api.giphy.com',
      text.isEmpty ? '/v1/gifs/trending' : '/v1/gifs/search',
      {
        'api_key': key,
        'limit': '$page',
        'offset': '$offset',
        'rating': rating.code,
        'bundle': 'messaging_non_clips',
        if (text.isNotEmpty) 'q': text,
      },
    );
    final bytes = await Web.fetch(uri, limit: 2 * 1024 * 1024);
    Web.held -= Web.memory.remove(uri.toString())?.length ?? 0;
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    final results = <Gif>[];
    for (final item in body['data'] as List<dynamic>? ?? const []) {
      final images = (item as Map<String, dynamic>)['images'];
      if (images is! Map<String, dynamic>) continue;
      final small = ['fixed_width_downsampled', 'fixed_width', 'preview_gif']
          .map((name) => images[name])
          .whereType<Map<String, dynamic>>()
          .where((value) => value['url'] is String);
      final large = ['downsized', 'fixed_height', 'original']
          .map((name) => images[name])
          .whereType<Map<String, dynamic>>()
          .where((value) => value['url'] is String);
      if (small.isEmpty || large.isEmpty) continue;
      results.add(
        Gif(
          id: item['id'] as String? ?? '',
          title: item['title'] as String? ?? '',
          preview: Uri.parse(small.first['url'] as String),
          full: Uri.parse(large.first['url'] as String),
          width: int.tryParse('${large.first['width']}') ?? 0,
          height: int.tryParse('${large.first['height']}') ?? 0,
        ),
      );
    }
    return results;
  }
}
