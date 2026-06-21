import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/services/web.dart';
import 'package:zephyron/widgets/sheet.dart';

typedef Picked = ({Uint8List bytes, Gif gif});

class Gifs extends StatefulWidget {
  const Gifs({super.key});

  static Future<Picked?> show(BuildContext context) {
    return showModalBottomSheet<Picked>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const Gifs(),
    );
  }

  @override
  State<Gifs> createState() => GifsState();
}

class GifsState extends State<Gifs> {
  final TextEditingController search = TextEditingController();
  final ScrollController scroll = ScrollController();
  final List<Gif> results = [];
  Timer? debounce;
  bool loading = false;
  bool exhausted = false;
  String? problem;
  String? picking;
  int request = 0;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.extentAfter < 600) more();
    });
    if (Giphy.ready) more(reset: true);
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> more({bool reset = false}) async {
    if (!reset && (loading || exhausted)) return;
    final ticket = ++request;
    setState(() {
      loading = true;
      problem = null;
      if (reset) {
        results.clear();
        exhausted = false;
      }
    });
    try {
      final page = await Giphy.query(
        search.text.trim(),
        results.length,
        Courier.instance.prefs.rating,
      );
      if (!mounted || ticket != request) return;
      setState(() {
        results.addAll(page);
        exhausted = page.length < Giphy.page;
        loading = false;
      });
    } catch (_) {
      if (!mounted || ticket != request) return;
      setState(() {
        loading = false;
        problem = Courier.instance.reach.value == Reach.online
            ? 'GIPHY could not be reached over Tor. Pull to retry.'
            : 'Waiting for Tor before GIFs can load.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.82;

    Widget body;
    if (!Giphy.ready) {
      body = Notice(
        icon: Icons.key_rounded,
        title: 'GIPHY key missing',
        text:
            'Add GIPHY_API_KEY to .env and build with --dart-define-from-file=.env to enable GIFs.',
      );
    } else if (results.isEmpty && problem != null) {
      body = Notice(
        icon: Icons.cloud_off_rounded,
        title: 'No GIFs right now',
        text: problem!,
        action: TextButton(
          onPressed: () => more(reset: true),
          child: const Text('Retry'),
        ),
      );
    } else if (results.isEmpty && loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (results.isEmpty) {
      body = Notice(
        icon: Icons.search_off_rounded,
        title: 'Nothing found',
        text: 'Try a different search.',
      );
    } else {
      body = GridView.builder(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.25,
        ),
        itemCount: results.length + (loading ? 2 : 0),
        itemBuilder: (context, index) {
          if (index >= results.length) {
            return Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
            );
          }
          final gif = results[index];
          return GestureDetector(
            onTap: () async {
              if (picking != null) return;
              setState(() => picking = gif.id);
              try {
                final bytes = await Web.fetch(gif.full);
                if (context.mounted) {
                  Navigator.pop<Picked>(context, (bytes: bytes, gif: gif));
                }
              } catch (_) {
                if (!context.mounted) return;
                setState(() => picking = null);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text('That GIF failed to download. Try another.'),
                  ),
                );
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TorImage(uri: gif.preview),
                  if (picking == gif.id)
                    Container(
                      color: Colors.black45,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }

    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Sheets.grabber(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              controller: search,
              enabled: Giphy.ready,
              decoration: InputDecoration(
                hintText: 'Search GIPHY…',
                prefixIcon: const Icon(Icons.gif_box_outlined),
              ),
              onChanged: (_) {
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 450),
                  () => more(reset: true),
                );
              },
            ),
          ),
          Expanded(child: body),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Powered by GIPHY · loaded over Tor',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class TorImage extends StatefulWidget {
  final Uri uri;
  final BoxFit fit;

  const TorImage({super.key, required this.uri, this.fit = BoxFit.cover});

  @override
  State<TorImage> createState() => TorImageState();
}

class TorImageState extends State<TorImage> {
  late Future<Uint8List> bytes = Web.fetch(widget.uri);

  @override
  void didUpdateWidget(TorImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) bytes = Web.fetch(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: data != null
              ? Image.memory(
                  data,
                  key: const ValueKey('image'),
                  fit: widget.fit,
                  gaplessPlayback: true,
                )
              : Container(
                  key: const ValueKey('wait'),
                  color: scheme.surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: snapshot.hasError
                      ? Icon(
                          Icons.broken_image_outlined,
                          color: scheme.onSurfaceVariant,
                        )
                      : null,
                ),
        );
      },
    );
  }
}

class Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  const Notice({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
