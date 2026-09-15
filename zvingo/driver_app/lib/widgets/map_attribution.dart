import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';

/// The raster basemaps this app draws, with the credit each one legally
/// requires.
///
/// Finding X7: five of the six `FlutterMap` widgets in the two Flutter apps
/// rendered CARTO tiles with no attribution at all. OpenStreetMap data is
/// ODbL — credit is a licence condition, not a courtesy — and CARTO's basemap
/// terms require their own credit alongside it. Keeping the URL and its
/// attribution in one enum makes it impossible to add a tile layer here and
/// forget the credit.
enum MapBasemap {
  /// Colour basemap. Best for at-a-glance route context.
  voyager(
    label: 'Streets',
    icon: Icons.map_outlined,
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
  ),

  /// Low-contrast basemap. Markers, heat and routes read far better on it in
  /// direct sunlight, which is where this app is used.
  positron(
    label: 'Plain',
    icon: Icons.layers_outlined,
    urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
  ),

  /// Dark basemap, for night shifts.
  darkMatter(
    label: 'Night',
    icon: Icons.dark_mode_outlined,
    urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
  );

  const MapBasemap({
    required this.label,
    required this.icon,
    required this.urlTemplate,
  });

  /// Short name shown on the basemap switcher.
  final String label;

  /// Glyph for the switcher.
  final IconData icon;

  /// CARTO raster tile template.
  final String urlTemplate;

  /// CARTO serves these from a, b, c and d.
  List<String> get subdomains => const ['a', 'b', 'c', 'd'];

  /// The next basemap in the cycle, for a one-tap switcher.
  MapBasemap get next =>
      MapBasemap.values[(index + 1) % MapBasemap.values.length];

  /// Sent as the tile request's User-Agent so OSM/CARTO can identify this
  /// client, as both ask.
  static const String userAgentPackageName = 'com.zvingo.driver';

  /// The credit line every layer must display.
  static const String credit = '© OpenStreetMap contributors · © CARTO';
}

/// The attribution overlay for a `FlutterMap`.
///
/// Add it as the **last** child of `FlutterMap` so it draws over the tiles.
/// It is intentionally small, low-contrast and non-interactive: it satisfies
/// the licence without competing with the route for a driver's one second of
/// attention.
///
/// ```dart
/// FlutterMap(
///   children: [TileLayer(...), MarkerLayer(...), const MapAttribution()],
/// )
/// ```
class MapAttribution extends StatelessWidget {
  /// Extra bottom inset, for maps with a panel or footer over the bottom edge.
  final double bottomInset;

  const MapAttribution({super.key, this.bottomInset = 0});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.only(
          right: AppSpacing.sm,
          bottom: AppSpacing.sm + bottomInset,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context).withValues(alpha: 0.82),
            borderRadius: AppSpacing.brSm,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            child: Text(
              MapBasemap.credit,
              style: AppTextStyles.onSurface(
                context,
                AppTextStyles.overline.copyWith(
                  letterSpacing: 0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
