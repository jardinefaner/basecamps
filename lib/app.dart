import 'package:basecamp/router.dart';
import 'package:basecamp/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BasecampApp extends ConsumerWidget {
  const BasecampApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Basecamp',
      theme: lightTheme(),
      darkTheme: darkTheme(),
      routerConfig: router,
    );
  }
}
