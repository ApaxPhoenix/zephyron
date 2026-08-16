import 'package:flutter/material.dart';
import 'dart:developer' as developer;

class MessagePage extends StatefulWidget {
  final String? title;
  final String? id;

  const MessagePage({super.key, this.title, this.id});

  @override
  State<MessagePage> createState() => MessagePageState();
}

class MessagePageState extends State<MessagePage> {
  final TextEditingController input = TextEditingController();
  final ScrollController scroll = ScrollController();

  late String title;
  late String id;

  List<Map<String, dynamic>> messages = [
    {
      'id': '1',
      'text': 'Routing circuit established over onion v3.',
      'time': '10:38 AM',
      'mine': false,
    },
    {
      'id': '2',
      'text': 'Acknowledged. Awaiting payload verification.',
      'time': '10:40 AM',
      'mine': true,
    },
    {
      'id': '3',
      'text': 'Encrypted payload confirmed at block 842.',
      'time': '10:42 AM',
      'mine': false,
    },
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final data = ModalRoute.of(context)?.settings.arguments;
    if (data is Map<String, dynamic>) {
      title =
          widget.title ??
          data['name'] as String? ??
          data['title'] as String? ??
          'Alpha Node';
      id = widget.id ?? data['id'] as String? ?? '1';
    } else if (data is String) {
      title = widget.title ?? data;
      id = widget.id ?? '1';
    } else {
      title = widget.title ?? 'Alpha Node';
      id = widget.id ?? '1';
    }
  }

  void send() {
    final text = input.text.trim();
    if (text.isEmpty) return;

    setState(() {
      messages.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'text': text,
        'time': 'Just now',
        'mine': true,
      });
      input.clear();
    });

    bottom();
  }

  void bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    try {
      final colors = Theme.of(context).colorScheme;

      return Scaffold(
        backgroundColor: colors.surface,
        appBar: AppBar(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0.0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: colors.onSurface),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colors.surfaceContainerHighest,
                child: Text(
                  title.isNotEmpty ? title[0] : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Encrypted • Active Node',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: colors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.phone_outlined, color: colors.primary),
              onPressed: () {},
            ),
            IconButton(
              icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
              onPressed: () {},
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final item = messages[index];
                  final bool mine = item['mine'] == true;

                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: mine
                            ? colors.primary
                            : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(mine ? 16 : 4),
                          bottomRight: Radius.circular(mine ? 4 : 16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: mine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['text'] as String,
                            style: TextStyle(
                              color: mine ? colors.onPrimary : colors.onSurface,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['time'] as String,
                            style: TextStyle(
                              fontSize: 10,
                              color: mine
                                  ? colors.onPrimary.withAlpha(180)
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                color: colors.surface,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: colors.primary,
                      ),
                      onPressed: () {},
                    ),
                    Expanded(
                      child: TextField(
                        controller: input,
                        style: TextStyle(color: colors.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Type encrypted message...',
                          hintStyle: TextStyle(color: colors.onSurfaceVariant),
                          filled: true,
                          fillColor: colors.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded),
                      onPressed: send,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } catch (error) {
      developer.log(
        'Failed to render message screen layout: $error',
        name: 'MessagePage.build',
        error: error,
        stackTrace: StackTrace.current,
      );
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    try {
      input.dispose();
      scroll.dispose();
      super.dispose();
    } catch (error) {
      developer.log(
        'Failed to dispose message screen resources: $error',
        name: 'MessagePage.dispose',
        error: error,
        stackTrace: StackTrace.current,
      );
    }
  }
}
