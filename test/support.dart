import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/identity.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/sql/database.dart' as store;
import 'package:zephyron/sql/ledger.dart';

final alice = Identity.fromInput('alice test seed phrase');
final bob = Identity.fromInput('bob test seed phrase');
final carol = Identity.fromInput('carol test seed phrase');

class Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String root = Directory.systemTemp.createTempSync('zephyron_test').path;

  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';

  @override
  Future<String?> getTemporaryPath() async => '$root/temporary';
}

Future<void> unlock() async {
  sqfliteFfiInit();
  PathProviderPlatform.instance = Paths();
  await store.Database.databaseInstance?.close();
  store.Database.databaseInstance = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await Ledger.ensure();
}

void become(Identity identity) {
  Courier.instance.self = identity;
  Courier.instance.secret = ed25519.PrivateKey(
    Courier.decode(identity.private),
  );
}

void reset() {
  final courier = Courier.instance;
  courier.roster.clear();
  courier.threads.clear();
  courier.presence.clear();
  courier.channels.clear();
  courier.transfers.clear();
  courier.progress.clear();
  courier.waiting.clear();
  courier.focus = null;
  become(bob);
}

Map<String, dynamic> sealed(
  Identity from,
  Signal kind, {
  String? id,
  String body = '',
  Identity? to,
}) {
  final current = Courier.instance.self!;
  become(from);
  final frame = Courier.instance.seal(
    kind,
    (to ?? current).address,
    id: id,
    body: body,
  );
  become(current);
  return frame;
}

class Wire {
  final Socket client;
  final Socket server;
  final List<Map<String, dynamic>> replies = [];
  final StreamController<Map<String, dynamic>> incoming =
      StreamController.broadcast();
  bool closed = false;

  Wire(this.client, this.server) {
    client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final frame = jsonDecode(line) as Map<String, dynamic>;
            replies.add(frame);
            incoming.add(frame);
          },
          onDone: () => closed = true,
          onError: (_) => closed = true,
        );
  }

  static Future<Wire> open() async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );
    final server = await listener.first;
    await listener.close();
    Courier.instance.adopt(Channel(server, inbound: true), server);
    return Wire(client, server);
  }

  void send(Map<String, dynamic> frame) {
    client.write('${jsonEncode(frame)}\n');
  }

  Future<Map<String, dynamic>> reply(String kind, String id) {
    final found = replies.where(
      (frame) => frame['kind'] == kind && frame['id'] == id,
    );
    if (found.isNotEmpty) return Future.value(found.first);
    return incoming.stream
        .firstWhere((frame) => frame['kind'] == kind && frame['id'] == id)
        .timeout(const Duration(seconds: 5));
  }

  Future<void> close() async {
    client.destroy();
    server.destroy();
  }
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was never met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Uint8List pattern(int length) =>
    Uint8List.fromList(List.generate(length, (index) => index * 7 % 251));
