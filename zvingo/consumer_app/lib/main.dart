import 'package:consumer_app/core/theme.dart';
import 'package:consumer_app/core/router.dart';
import 'package:consumer_app/core/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/core/hive_init.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  await HiveInit.init();

  runApp(const ProviderScope(child: ZvingoConsumerApp()));
}

class ZvingoConsumerApp extends ConsumerWidget {
  const ZvingoConsumerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Zvingo',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'zvingo',
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
