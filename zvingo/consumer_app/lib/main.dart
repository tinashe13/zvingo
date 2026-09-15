import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_config.dart';
import 'package:consumer_app/core/hive_init.dart';
import 'package:consumer_app/core/router.dart';
import 'package:consumer_app/core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  await HiveInit.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ProviderScope(child: ZvingoConsumerApp()));
}

/// Root of the Zvingo consumer app.
class ZvingoConsumerApp extends ConsumerWidget {
  const ZvingoConsumerApp({super.key});

  /// Text scale is clamped so the design system's fixed-height controls
  /// (§5.1 buttons, §5.3 inputs) survive very large system font settings
  /// without overflowing. 2.0 still satisfies the "works at 200% text scale"
  /// review bar (§7).
  static const double _maxTextScale = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Zvingo',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'zvingo',
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: _maxTextScale,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
