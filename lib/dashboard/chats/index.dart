import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:zephyron/main.dart';
import 'package:zephyron/theme.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => ChatsPageState();
}

class ChatsPageState extends State<ChatsPage> {
  String? avatar;

  @override
  void initState() {
    super.initState();
    account.get().then((user) {
      tables
          .listRows(
            databaseId: '69951d1f002692e40827',
            tableId: '69965edb0019ed7a133f',
            queries: [Query.equal('email', user.email)],
          )
          .then((rows) {
            if (mounted && rows.rows.isNotEmpty) {
              setState(
                () => avatar = rows.rows.first.data['avatar'] as String?,
              );
            }
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: avatar != null
                ? Image.network(
                    avatar!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Pallete.neutral100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      PhosphorIconsRegular.user,
                      size: 20,
                      color: Pallete.neutral500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
