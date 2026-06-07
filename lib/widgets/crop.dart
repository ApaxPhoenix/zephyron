import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Full-screen editor that frames a picture before it becomes an avatar or a
/// banner. Drag to move, pinch or use the slider to zoom; the result is a
/// small JPEG of exactly the framed area.
class Cropper extends StatefulWidget {
  final Uint8List bytes;

  /// Width divided by height of the frame.
  final double aspect;

  /// Shows a circular frame, for avatars.
  final bool round;

  /// Pixel width of the image handed back.
  final int width;

  final String title;

  const Cropper({
    super.key,
    required this.bytes,
    this.aspect = 1,
    this.round = true,
    this.width = 512,
    this.title = 'Crop Photo',
  });

  static Future<Uint8List?> open(
    BuildContext context,
    Uint8List bytes, {
    double aspect = 1,
    bool round = true,
    int width = 512,
    String title = 'Crop Photo',
  }) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Cropper(
          bytes: bytes,
          aspect: aspect,
          round: round,
          width: width,
          title: title,
        ),
      ),
    );
  }

  /// Cuts [area] (in source pixels) out of [bytes] and scales it to [width].
  static Uint8List cut(Uint8List bytes, Rect area, int width, double aspect) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const FormatException('Unreadable picture');
    final upright = img.bakeOrientation(decoded);
    final left = area.left.round().clamp(0, upright.width - 1);
    final top = area.top.round().clamp(0, upright.height - 1);
    final cropped = img.copyCrop(
      upright,
      x: left,
      y: top,
      width: area.width.round().clamp(1, upright.width - left),
      height: area.height.round().clamp(1, upright.height - top),
    );
    final scaled = img.copyResize(
      cropped,
      width: width,
      height: (width / aspect).round(),
      interpolation: img.Interpolation.average,
    );
    return img.encodeJpg(scaled, quality: 85);
  }

  /// Shrinks an animated GIF until it is at most [limit] bytes, keeping the
  /// animation. Returns null when even the smallest size is too large.
  static Uint8List? shrink(Uint8List bytes, int limit) {
    if (bytes.length <= limit) return bytes;
    final animation = img.decodeGif(bytes);
    if (animation == null) return null;
    for (final width in [480, 400, 320, 240, 180]) {
      if (width >= animation.width) continue;
      final smaller = img.copyResize(
        animation,
        width: width,
        interpolation: img.Interpolation.average,
      );
      final encoded = img.encodeGif(smaller, samplingFactor: 20);
      if (encoded.length <= limit) return encoded;
    }
    return null;
  }

  /// Whether [bytes] start with a GIF signature.
  static bool animated(Uint8List bytes) =>
      bytes.length > 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46;

  @override
  State<Cropper> createState() => CropperState();
}

class CropperState extends State<Cropper> {
  ui.Image? picture;
  double zoom = 1;
  Offset shift = Offset.zero;
  double grip = 1;
  Offset anchor = Offset.zero;
  Offset hold = Offset.zero;
  Size frame = Size.zero;
  bool busy = false;

  static const double ceiling = 5;

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.bytes).then((image) {
      if (mounted) setState(() => picture = image);
    });
  }

  @override
  void dispose() {
    picture?.dispose();
    super.dispose();
  }

  /// Scale from source pixels to screen points.
  double scale(Size frame) {
    final image = picture!;
    final cover = math.max(
      frame.width / image.width,
      frame.height / image.height,
    );
    return cover * zoom;
  }

  /// Keeps the picture covering the whole frame.
  Offset fit(Offset offset, Size frame) {
    final image = picture!;
    final factor = scale(frame);
    final spareX = math.max(0.0, (image.width * factor - frame.width) / 2);
    final spareY = math.max(0.0, (image.height * factor - frame.height) / 2);
    return Offset(
      offset.dx.clamp(-spareX, spareX),
      offset.dy.clamp(-spareY, spareY),
    );
  }

  Future<void> done() async {
    final image = picture;
    if (image == null || busy) return;
    setState(() => busy = true);
    final factor = scale(frame);
    final area = Rect.fromLTWH(
      ((image.width * factor - frame.width) / 2 - shift.dx) / factor,
      ((image.height * factor - frame.height) / 2 - shift.dy) / factor,
      frame.width / factor,
      frame.height / factor,
    );
    final bytes = widget.bytes;
    final width = widget.width;
    final aspect = widget.aspect;
    try {
      final result = await Isolate.run(
        () => Cropper.cut(bytes, area, width, aspect),
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not crop that picture.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const ink = Color(0xFF0E0E10);

    return Scaffold(
      backgroundColor: ink,
      appBar: AppBar(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        shape: const Border(),
        title: Text(
          widget.title,
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
        ),
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
              onPressed: picture == null || busy ? null : done,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Apply'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final image = picture;
                  if (image == null) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  var width = box.maxWidth - 48;
                  var height = width / widget.aspect;
                  if (height > box.maxHeight - 48) {
                    height = box.maxHeight - 48;
                    width = height * widget.aspect;
                  }
                  frame = Size(width, height);
                  final factor = scale(frame);
                  final shown = Size(
                    image.width * factor,
                    image.height * factor,
                  );
                  final center = Offset(box.maxWidth / 2, box.maxHeight / 2);
                  final hole = Rect.fromCenter(
                    center: center,
                    width: width,
                    height: height,
                  );

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (details) {
                      grip = zoom;
                      anchor = details.focalPoint;
                      hold = shift;
                    },
                    onScaleUpdate: (details) => setState(() {
                      zoom = (grip * details.scale).clamp(1.0, ceiling);
                      shift = fit(hold + details.focalPoint - anchor, frame);
                    }),
                    child: Stack(
                      children: [
                        Positioned(
                          left: center.dx + shift.dx - shown.width / 2,
                          top: center.dy + shift.dy - shown.height / 2,
                          width: shown.width,
                          height: shown.height,
                          child: RawImage(image: image, fit: BoxFit.fill),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: Mask(
                                hole: hole,
                                round: widget.round,
                                scrim: ink.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.photo_size_select_small,
                        color: Colors.white70,
                        size: 20,
                      ),
                      Expanded(
                        child: Slider(
                          value: zoom,
                          min: 1,
                          max: ceiling,
                          activeColor: scheme.primary,
                          inactiveColor: Colors.white24,
                          onChanged: picture == null
                              ? null
                              : (value) => setState(() {
                                  zoom = value;
                                  shift = fit(shift, frame);
                                }),
                        ),
                      ),
                      const Icon(
                        Icons.photo_size_select_large,
                        color: Colors.white70,
                        size: 24,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Drag to move · Pinch to zoom',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Darkens everything outside the frame and outlines it.
class Mask extends CustomPainter {
  final Rect hole;
  final bool round;
  final Color scrim;

  const Mask({required this.hole, required this.round, required this.scrim});

  @override
  void paint(Canvas canvas, Size size) {
    final shape = round
        ? (Path()..addOval(hole))
        : (Path()..addRRect(
            RRect.fromRectAndRadius(hole, const Radius.circular(16)),
          ));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        shape,
      ),
      Paint()..color = scrim,
    );
    canvas.drawPath(
      shape,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(Mask old) =>
      old.hole != hole || old.round != round || old.scrim != scrim;
}
