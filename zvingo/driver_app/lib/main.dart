import 'package:driver_app/core/theme.dart';
import 'package:driver_app/core/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:driver_app/core/hive_init.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveInit.init();

  runApp(const ProviderScope(child: ZvingoDriverApp()));
}

class ZvingoDriverApp extends ConsumerWidget {
  const ZvingoDriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Zvingo Driver',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
