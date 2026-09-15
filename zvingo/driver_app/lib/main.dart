import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/hive_init.dart';
import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The driver app is used one-handed on a vehicle; locking to portrait keeps
  // the primary action in the same thumb-reachable place every time.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await HiveInit.init();

  runApp(const ProviderScope(child: ZvingoDriverApp()));
}

/// Root of the Zvingo driver app.
class ZvingoDriverApp extends ConsumerWidget {
  const ZvingoDriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Zvingo Driver',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      // Drivers work nights. Dark mode is a real theme here, and it follows
      // whatever the phone is set to rather than being a buried preference.
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Cap text scaling so a driver running 200% system text still gets a
        // laid-out screen rather than an overflow, without ignoring their
        // accessibility setting entirely.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.6,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
