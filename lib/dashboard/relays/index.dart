import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zephyron/enums.dart';
import 'package:zephyron/models/message.dart';
import 'package:zephyron/services/courier.dart';
import 'package:zephyron/theme.dart';
import 'package:zephyron/widgets/avatar.dart';
import 'package:zephyron/widgets/beacon.dart';
import 'package:zephyron/widgets/section.dart';
import 'package:zephyron/widgets/stamp.dart';
import 'package:zephyron/wrappers/tor.dart';

class RelaysPage extends StatefulWidget {
  const RelaysPage({super.key});

  @override
  State<RelaysPage> createState() => RelaysPageState();
}

class RelaysPageState extends State<RelaysPage> {
  final TextEditingController lines = TextEditingController();
  List<Circuit> circuits = [];
  ({String version, int read, int written})? vitals;
  Timer? poll;
  bool bridging = false;
  bool saving = false;
  bool renewing = false;
  String? problem;
  int crowd = 0;
  int route = 0;

  /// People on your node shown per page.
  static const int visitors = 6;

  /// Circuit cards shown per page; each lists every hop, so they are tall.
  static const int routes = 2;

  Courier get courier => Courier.instance;
  Sentinel get sentinel => Sentinel.summon();

  @override
  void initState() {
    super.initState();
    sentinel.bridges().then((saved) {
      if (!mounted) return;
      setState(() {
        bridging = saved.enabled;
        lines.text = saved.lines.join('\n');
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
    poll = Timer.periodic(const Duration(seconds: 6), (_) => refresh());
  }

  @override
  void dispose() {
    poll?.cancel();
    lines.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (sentinel.progress.value != 100) return;
    try {
      final status = await sentinel.vitals();
      final built = await sentinel.circuits();
      if (!mounted) return;
      setState(() {
        vitals = status;
        circuits = built;
      });
    } catch (_) {}
  }

  Widget page(BuildContext context, List<Widget> children) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.onSurface,
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 20, 16, 32 + inset),
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tabular = const [FontFeature.tabularFigures()];
    final calm = MediaQuery.disableAnimationsOf(context);
    const top = EdgeInsets.fromLTRB(4, 0, 0, 12);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Network'),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: Beacon()),
            ),
          ],
          bottom: TabBar(
            dividerHeight: 0,
            labelStyle: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            unselectedLabelStyle: Theme.of(context).textTheme.labelLarge,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Node'),
              Tab(text: 'Circuits'),
              Tab(text: 'Bridges'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([
            courier,
            courier.reach,
            sentinel.progress,
          ]),
          builder: (context, _) {
            final progress = sentinel.progress.value;
            final reach = courier.reach.value;
            final connections = courier.live.toList()
              ..sort((alpha, beta) => beta.opened.compareTo(alpha.opened));
            final crowds = Pager.count(connections.length, visitors);
            final crowding = crowd.clamp(0, crowds - 1);
            final roads = Pager.count(circuits.length, routes);
            final routing = route.clamp(0, roads - 1);
            final tabs = DefaultTabController.of(context);

            Widget visitor(Channel channel) {
              return Builder(
                builder: (context) {
                  final peer = channel.peer;
                  final known = peer == null ? null : courier.roster[peer];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    onTap: peer == null
                        ? null
                        : () => Navigator.pushNamed(
                            context,
                            '/dashboard/peers/node',
                            arguments: {'id': peer},
                          ),
                    leading: peer == null
                        ? Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: scheme.outline),
                            ),
                            child: Icon(
                              Icons.person_outline,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : Portrait(address: peer, size: 40),
                    title: Text(
                      known?.label ??
                          (peer == null ? 'Anonymous' : peer.substring(0, 10)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${channel.inbound ? 'Joined your node' : 'You connected'} ${ago(channel.opened)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final line in [
                          '↓ ${measure(channel.received)}',
                          '↑ ${measure(channel.sent)}',
                        ])
                          Text(
                            line,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontFamily: Pallete.mono,
                                  fontFeatures: tabular,
                                ),
                          ),
                      ],
                    ),
                  );
                },
              );
            }

            Widget jump(
              IconData icon,
              String title,
              String subtitle,
              int index, {
              int? count,
            }) {
              return ListTile(
                onTap: () => tabs.animateTo(index),
                leading: Icon(icon),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (count != null) Pill(count: count),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              );
            }

            return TabBarView(
              children: [
                page(context, [
                  Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Row(
                            children: [
                              Text(
                                'Tor',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              AnimatedSwitcher(
                                duration: Duration(
                                  milliseconds: calm ? 0 : 200,
                                ),
                                child: Text(
                                  switch (reach) {
                                    Reach.online => 'Bootstrapped',
                                    Reach.connecting =>
                                      progress > 0
                                          ? 'Bootstrapping $progress%'
                                          : 'Starting…',
                                    Reach.offline => 'Unavailable',
                                  },
                                  key: ValueKey('$reach$progress'),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontFeatures: tabular),
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedSize(
                          duration: Duration(milliseconds: calm ? 0 : 220),
                          child: reach == Reach.connecting
                              ? LinearProgressIndicator(
                                  minHeight: 2,
                                  value: progress > 0 ? progress / 100 : null,
                                )
                              : const Divider(),
                        ),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              for (final (label, value) in [
                                (
                                  'Received',
                                  vitals == null ? '—' : measure(vitals!.read),
                                ),
                                (
                                  'Sent',
                                  vitals == null
                                      ? '—'
                                      : measure(vitals!.written),
                                ),
                                ('Circuits', '${circuits.length}'),
                              ]) ...[
                                if (label != 'Received')
                                  VerticalDivider(
                                    width: 1,
                                    color: scheme.outline,
                                  ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          label,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 6),
                                        AnimatedSwitcher(
                                          duration: Duration(
                                            milliseconds: calm ? 0 : 200,
                                          ),
                                          layoutBuilder: (current, previous) =>
                                              Stack(
                                                alignment: Alignment.centerLeft,
                                                children: [
                                                  ...previous,
                                                  ?current,
                                                ],
                                              ),
                                          child: Text(
                                            value,
                                            key: ValueKey(value),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontFeatures: tabular,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  vitals == null
                                      ? 'Version unknown'
                                      : 'Tor ${vitals!.version}',
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontFamily: Pallete.mono),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: renewing || progress != 100
                                    ? null
                                    : () async {
                                        setState(() => renewing = true);
                                        try {
                                          await sentinel.order('SIGNAL NEWNYM');
                                          await Future<void>.delayed(
                                            const Duration(seconds: 2),
                                          );
                                          await refresh();
                                        } catch (_) {
                                        } finally {
                                          if (mounted) {
                                            setState(() => renewing = false);
                                          }
                                        }
                                      },
                                icon: AnimatedRotation(
                                  turns: renewing ? 1 : 0,
                                  duration: Duration(
                                    milliseconds: calm ? 0 : 900,
                                  ),
                                  child: const Icon(Icons.refresh, size: 18),
                                ),
                                label: const Text('New Circuits'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Heading('At a Glance'),
                  Group(
                    children: [
                      jump(
                        Icons.sensors,
                        'On Your Node',
                        'Everyone connected to you right now',
                        1,
                        count: connections.length,
                      ),
                      jump(
                        Icons.route_outlined,
                        'Circuits',
                        progress == 100
                            ? 'Relays your traffic travels through'
                            : 'Waiting for Tor to bootstrap',
                        2,
                        count: progress == 100 ? circuits.length : null,
                      ),
                      jump(
                        Icons.alt_route,
                        'Bridges',
                        bridging
                            ? 'On, first hop goes through unlisted relays'
                            : 'Off, connecting to Tor directly',
                        3,
                      ),
                    ],
                  ),
                ]),
                page(context, [
                  Heading(
                    'On Your Node',
                    count: connections.length,
                    padding: top,
                    description:
                        'Everyone connected to your onion service right now. Tor hides their IP addresses, so trustees are recognised by their signed discovery key.',
                  ),
                  if (connections.isEmpty)
                    const Vacant(
                      icon: Icons.sensors_off_outlined,
                      text: 'Nobody is connected right now.',
                    )
                  else
                    Group(
                      indent: 72,
                      children: [
                        for (final channel in Pager.slice(
                          connections,
                          crowding,
                          visitors,
                        ))
                          visitor(channel),
                      ],
                    ),
                  if (crowds > 1)
                    Pager(
                      page: crowding,
                      pages: crowds,
                      onChanged: (next) => setState(() => crowd = next),
                    ),
                ]),
                page(context, [
                  Heading(
                    'Circuits',
                    count: progress == 100 ? circuits.length : null,
                    padding: top,
                    description:
                        'The relays your traffic travels through. No single relay sees both where it comes from and where it goes.',
                  ),
                  if (circuits.isEmpty)
                    Vacant(
                      icon: Icons.route_outlined,
                      text: progress == 100
                          ? 'Tor has not built any circuits yet.'
                          : 'Circuits appear once Tor has bootstrapped.',
                    ),
                  for (final circuit in Pager.slice(
                    circuits,
                    routing,
                    routes,
                  )) ...[
                    Card(
                      key: ValueKey('circuit:${circuit.id}'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    () {
                                      final peer = courier
                                          .roster['${circuit.target}.onion'];
                                      final purpose = switch (circuit.purpose) {
                                        'GENERAL' => 'General',
                                        'HS_CLIENT_HSDIR' ||
                                        'HS_CLIENT_INTRO' =>
                                          'Looking Up a Peer',
                                        'HS_CLIENT_REND' => 'Talking to a Peer',
                                        'HS_SERVICE_HSDIR' =>
                                          'Publishing Your Node',
                                        'HS_SERVICE_INTRO' =>
                                          'Introduction Point for Your Node',
                                        'HS_SERVICE_REND' =>
                                          'A Peer Talking to You',
                                        'HS_VANGUARDS' => 'Vanguards',
                                        'CONFLUX_LINKED' ||
                                        'CONFLUX_UNLINKED' => 'Conflux',
                                        'MEASURE_TIMEOUT' => 'Measuring Speed',
                                        _ => 'Circuit ${circuit.id}',
                                      };
                                      return peer == null
                                          ? purpose
                                          : '$purpose: ${peer.label}';
                                    }(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                if (circuit.created != null)
                                  Text(
                                    ago(circuit.created!.toLocal()),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontFeatures: tabular),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            for (
                              var index = 0;
                              index < circuit.path.length;
                              index++
                            )
                              Builder(
                                builder: (context) {
                                  final relay = circuit.path[index];
                                  final last = index == circuit.path.length - 1;
                                  final marks = relay.flags
                                      .where(
                                        (item) => const {
                                          'Guard',
                                          'Exit',
                                          'Fast',
                                          'Stable',
                                          'HSDir',
                                        }.contains(item),
                                      )
                                      .toList();
                                  final role = index == 0
                                      ? 'Guard'
                                      : !last
                                      ? 'Middle'
                                      : circuit.purpose == 'GENERAL'
                                      ? 'Exit'
                                      : circuit.purpose.endsWith('INTRO')
                                      ? 'Introduction'
                                      : circuit.purpose.endsWith('REND')
                                      ? 'Rendezvous'
                                      : 'Last Hop';
                                  final flag = relay.country.length == 2
                                      ? String.fromCharCodes(
                                          relay.country
                                              .toUpperCase()
                                              .codeUnits
                                              .map(
                                                (unit) => 0x1F1E6 + unit - 65,
                                              ),
                                        )
                                      : '';
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(text: relay.fingerprint),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Copied fingerprint of ${relay.nickname.isEmpty ? 'relay' : relay.nickname}',
                                          ),
                                        ),
                                      );
                                    },
                                    child: IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            child: Column(
                                              children: [
                                                Container(
                                                  width: 1,
                                                  height: 12,
                                                  color: index == 0
                                                      ? Colors.transparent
                                                      : scheme.outline,
                                                ),
                                                Container(
                                                  width: 9,
                                                  height: 9,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: last
                                                        ? scheme.onSurface
                                                        : scheme.surface,
                                                    border: Border.all(
                                                      color: scheme.onSurface,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Container(
                                                    width: 1,
                                                    color: last
                                                        ? Colors.transparent
                                                        : scheme.outline,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                                bottom: 10,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Row(
                                                          children: [
                                                            Flexible(
                                                              child: Text(
                                                                relay
                                                                        .nickname
                                                                        .isEmpty
                                                                    ? 'Unnamed relay'
                                                                    : relay
                                                                          .nickname,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: Theme.of(
                                                                  context,
                                                                ).textTheme.labelLarge,
                                                              ),
                                                            ),
                                                            if (flag
                                                                .isNotEmpty) ...[
                                                              const SizedBox(
                                                                width: 6,
                                                              ),
                                                              Text(flag),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(
                                                        role,
                                                        style: Theme.of(
                                                          context,
                                                        ).textTheme.labelSmall,
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text.rich(
                                                    TextSpan(
                                                      children: [
                                                        TextSpan(
                                                          text:
                                                              relay
                                                                  .address
                                                                  .isEmpty
                                                              ? '${relay.fingerprint.substring(0, 16)}…'
                                                              : relay.address,
                                                          style:
                                                              const TextStyle(
                                                                fontFamily:
                                                                    Pallete
                                                                        .mono,
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                        if (marks.isNotEmpty)
                                                          TextSpan(
                                                            text:
                                                                '  ·  ${marks.join(' · ')}',
                                                          ),
                                                      ],
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (roads > 1)
                    Pager(
                      page: routing,
                      pages: roads,
                      onChanged: (next) => setState(() => route = next),
                    ),
                ]),
                page(context, [
                  const Heading(
                    'Bridges',
                    padding: top,
                    description:
                        'Use bridges if Tor is blocked where you are. Get obfs4 bridge lines from bridges.torproject.org and paste one per line.',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Use Bridges'),
                            subtitle: const Text(
                              'Route your first hop through unlisted relays',
                            ),
                            value: bridging,
                            onChanged: (value) =>
                                setState(() => bridging = value),
                          ),
                          AnimatedSize(
                            duration: Duration(milliseconds: calm ? 0 : 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: bridging
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: TextField(
                                      controller: lines,
                                      minLines: 3,
                                      maxLines: 8,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      style: const TextStyle(
                                        fontFamily: Pallete.mono,
                                        fontSize: 12,
                                      ),
                                      decoration: InputDecoration(
                                        hintText:
                                            'obfs4 192.0.2.10:443 FINGERPRINT cert=… iat-mode=0',
                                        errorText: problem,
                                        errorMaxLines: 4,
                                      ),
                                      onChanged: (_) {
                                        if (problem != null) {
                                          setState(() => problem = null);
                                        }
                                      },
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    final raw = lines.text
                                        .split('\n')
                                        .map((line) => line.trim())
                                        .where((line) => line.isNotEmpty)
                                        .toList();
                                    final clean = raw
                                        .map(Sentinel.sanitize)
                                        .whereType<String>()
                                        .toList();
                                    if (bridging &&
                                        clean.length != raw.length) {
                                      setState(
                                        () => problem =
                                            'Line ${raw.indexWhere((line) => Sentinel.sanitize(line) == null) + 1} is not a valid bridge. Use the format shown, one bridge per line.',
                                      );
                                      return;
                                    }
                                    if (bridging && clean.isEmpty) {
                                      setState(
                                        () => problem =
                                            'Paste at least one bridge line.',
                                      );
                                      return;
                                    }
                                    setState(() => saving = true);
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    try {
                                      final live = await sentinel.bridge(
                                        bridging,
                                        clean,
                                      );
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            live
                                                ? 'Bridges applied. Tor is reconnecting.'
                                                : 'Bridges saved. They apply the next time Tor starts.',
                                          ),
                                        ),
                                      );
                                    } catch (_) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Tor rejected these bridges. Check each line and try again.',
                                          ),
                                        ),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() => saving = false);
                                      }
                                    }
                                  },
                            child: AnimatedSwitcher(
                              duration: Duration(milliseconds: calm ? 0 : 200),
                              child: saving
                                  ? const SizedBox(
                                      key: ValueKey('busy'),
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Save Bridges',
                                      key: ValueKey('idle'),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}
