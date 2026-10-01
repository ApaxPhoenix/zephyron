import 'package:flutter/material.dart';
import 'package:zephyron/theme.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/widgets/sheet.dart';

class Discovery extends StatelessWidget {
  final String address;
  final String name;
  final bool own;

  const Discovery({
    super.key,
    required this.address,
    required this.name,
    this.own = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String address,
    required String name,
    bool own = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => Discovery(address: address, name: name, own: own),
    );
  }

  static void copy(BuildContext context, String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
        content: const Text('Discovery key copied'),
      ),
    );
  }

  static Future<void> spread(String address, String name, {bool own = false}) {
    final who = name.trim().isEmpty ? 'this person' : name.trim();
    final intro = own
        ? 'Add me as a trustee on Zephyron'
        : 'Add $who as a trustee on Zephyron';
    return SharePlus.instance.share(
      ShareParams(
        subject: intro,
        text:
            '$intro\n\n${Courier.link(address, name)}\n\nDiscovery key: $address',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Sheets.grabber(context),
          Text(
            own ? 'Your Discovery Key' : name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            own
                ? 'Anyone who scans or pastes this can request to become your trustee.'
                : 'Share this so others can add ${name.trim().isEmpty ? 'them' : name} as a trustee.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: QrImageView(
              data: Courier.link(address, name),
              size: 220,
              padding: EdgeInsets.zero,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.circle,
                color: scheme.primary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: Color(0xFF1A1B21),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SelectableText(
            address,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Pallete.mono,
              fontSize: 13,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => copy(context, address),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => spread(address, name, own: own),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
