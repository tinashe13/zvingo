import 'dart:ui';

import 'package:consumer_app/common/widgets/app_ui.dart';
import 'package:consumer_app/common/widgets/floating_app_dock.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/theme.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ZvingoUiPreview());

class ZvingoUiPreview extends StatelessWidget {
  const ZvingoUiPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zvingo UI preview',
      theme: AppTheme.lightTheme,
      home: const _PreviewShell(),
    );
  }
}

class _PreviewShell extends StatefulWidget {
  const _PreviewShell();

  @override
  State<_PreviewShell> createState() => _PreviewShellState();
}

class _PreviewShellState extends State<_PreviewShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = switch (Uri.base.queryParameters['screen']) {
      'map' || 'store' => 1,
      'search' || 'cart' => 2,
      'orders' => 3,
      'account' => 4,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      _HomePreview(),
      _MapPreview(),
      _SearchPreview(),
      _OrdersPreview(),
      _AccountPreview(),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('MOCK PREVIEW',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 8 + MediaQuery.paddingOf(context).bottom,
            child: FloatingAppDock(
              currentIndex: _index,
              onSelected: (value) => setState(() => _index = value),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomePreview extends StatefulWidget {
  const _HomePreview();

  @override
  State<_HomePreview> createState() => _HomePreviewState();
}

class _HomePreviewState extends State<_HomePreview> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (Uri.base.queryParameters['state'] == 'collapsed') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo(150);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DELIVER NOW',
                        style: TextStyle(
                            color: AppColors.brandGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 20),
                        const SizedBox(width: 5),
                        const Expanded(
                          child: Text('18 Willow Avenue, Harare',
                              style: AppTextStyles.titleMedium,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded),
                        const SizedBox(width: 8),
                        _PreviewHeaderAction(
                            icon: Icons.notifications_none_rounded,
                            onTap: () {}),
                        const SizedBox(width: 7),
                        _PreviewHeaderAction(
                            icon: Icons.shopping_bag_outlined, onTap: () {}),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SliverPersistentHeader(
              pinned: true,
              delegate: _PreviewShortcutHeaderDelegate(),
            ),
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 22),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your dinner shortcut',
                              style: TextStyle(
                                  fontSize: 21, fontWeight: FontWeight.w900)),
                          SizedBox(height: 6),
                          Text('Save 20% on selected local favourites.'),
                          SizedBox(height: 15),
                          _DarkPill(label: 'Explore offers'),
                        ],
                      ),
                    ),
                    Text('⚡', style: TextStyle(fontSize: 54)),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child:
                    Text('Popular near you', style: AppTextStyles.titleLarge),
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate(const [
                _RestaurantCard(
                    emoji: '🍗',
                    color: Color(0xFFFFD4A8),
                    name: 'Flame & Grain',
                    meta: '25–35 min · \$0 delivery',
                    rating: '4.8'),
                _RestaurantCard(
                    emoji: '🍜',
                    color: Color(0xFFFFC9C9),
                    name: 'Noodle Social',
                    meta: '20–30 min · \$1.49 delivery',
                    rating: '4.7'),
                _RestaurantCard(
                    emoji: '🥙',
                    color: Color(0xFFD8EFC7),
                    name: 'Green Table',
                    meta: '15–25 min · \$0 delivery',
                    rating: '4.9'),
              ]),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 118)),
          ],
        ),
      ),
    );
  }
}

class _PreviewHeaderAction extends StatelessWidget {
  const _PreviewHeaderAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
              color: AppColors.surfaceMuted, shape: BoxShape.circle),
          child: Icon(icon, size: 20),
        ),
      );
}

class _PreviewShortcutHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PreviewShortcutHeaderDelegate();

  @override
  double get maxExtent => 94;

  @override
  double get minExtent => 58;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: AppColors.white.withValues(alpha: overlapsContent ? .9 : .96),
          padding:
              EdgeInsets.fromLTRB(13, 8 - progress * 3, 13, 8 - progress * 3),
          child: Row(children: [
            _PreviewShrinkingShortcut(
                icon: Icons.lunch_dining_rounded,
                label: 'Burgers',
                selected: false,
                progress: progress),
            _PreviewShrinkingShortcut(
                icon: Icons.local_pizza_rounded,
                label: 'Pizza',
                selected: false,
                progress: progress),
            _PreviewShrinkingShortcut(
                icon: Icons.restaurant_rounded,
                label: 'Hot food',
                selected: true,
                progress: progress),
            _PreviewShrinkingShortcut(
                icon: Icons.local_grocery_store_rounded,
                label: 'Grocery',
                selected: false,
                progress: progress),
            _PreviewShrinkingShortcut(
                icon: Icons.directions_car_filled_rounded,
                label: 'Rides',
                selected: false,
                progress: progress),
          ]),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

class _PreviewShrinkingShortcut extends StatelessWidget {
  const _PreviewShrinkingShortcut({
    required this.icon,
    required this.label,
    required this.selected,
    required this.progress,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final double progress;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: EdgeInsets.symmetric(vertical: 10 - progress * 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.selectedDark : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16 - progress * 3),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 23 - progress * 4,
                color: selected ? AppColors.white : AppColors.textPrimary),
            SizedBox(height: 6 - progress * 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: AppTextStyles.labelSmall.copyWith(
                    color: selected ? AppColors.white : AppColors.textPrimary,
                    fontSize: 10.5 - progress,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _RestaurantCard extends StatelessWidget {
  const _RestaurantCard(
      {required this.emoji,
      required this.color,
      required this.name,
      required this.meta,
      required this.rating});
  final String emoji;
  final Color color;
  final String name;
  final String meta;
  final String rating;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 164,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(22)),
              child: Stack(
                children: [
                  Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 82))),
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Icon(Icons.favorite_border_rounded,
                            color: AppColors.textPrimary)),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppColors.selectedDark,
                          borderRadius: BorderRadius.circular(999)),
                      child: const Text('20% off',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text(name, style: AppTextStyles.titleMedium)),
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: AppColors.surfaceMuted, shape: BoxShape.circle),
                  child: Text(rating,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            Text(meta,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _MapPreview extends StatelessWidget {
  const _MapPreview();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          const Positioned.fill(
              child: CustomPaint(painter: _NearbyMapPainter())),
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 12,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x24000000), blurRadius: 14)
                  ]),
              child: Row(children: [
                Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.location_on_rounded, size: 21)),
                const SizedBox(width: 11),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('RESTAURANTS NEAR',
                          style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('18 Willow Avenue, Harare',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall),
                    ])),
                const Icon(Icons.keyboard_arrow_down_rounded),
              ]),
            ),
          ),
          const Positioned(
              left: 65,
              top: 205,
              child: _PreviewMapMarker(
                  icon: Icons.restaurant_rounded,
                  background: AppColors.white,
                  foreground: AppColors.textPrimary,
                  size: 44)),
          const Positioned(
              right: 66,
              top: 272,
              child: _PreviewMapMarker(
                  icon: Icons.restaurant_rounded,
                  background: AppColors.selectedDark,
                  foreground: AppColors.white,
                  size: 52)),
          const Positioned(
              left: 168,
              top: 390,
              child: _PreviewMapMarker(
                  icon: Icons.restaurant_rounded,
                  background: AppColors.white,
                  foreground: AppColors.textPrimary,
                  size: 44)),
          const Positioned(
              right: 45,
              top: 492,
              child: _PreviewMapMarker(
                  icon: Icons.restaurant_rounded,
                  background: AppColors.white,
                  foreground: AppColors.textPrimary,
                  size: 44)),
          const Positioned(
            left: 210,
            top: 315,
            child: _PreviewUserPin(),
          ),
          Positioned(
            right: 16,
            top: MediaQuery.paddingOf(context).top + 88,
            child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: AppColors.white, shape: BoxShape.circle),
                child: const Icon(Icons.my_location_rounded, size: 21)),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 104,
            child: AppSurface(
              color: AppColors.white.withValues(alpha: .95),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFC9C9),
                        borderRadius: BorderRadius.circular(15)),
                    alignment: Alignment.center,
                    child: const Text('🍜', style: TextStyle(fontSize: 34))),
                const SizedBox(width: 12),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Noodle Social', style: AppTextStyles.titleSmall),
                      SizedBox(height: 4),
                      Text('20–30 min · 1.4 km',
                          style: AppTextStyles.bodySmall),
                      SizedBox(height: 5),
                      Text('★ 4.7 · \$1.49 delivery',
                          style: AppTextStyles.labelSmall),
                    ])),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
          ),
        ]),
      );
}

class _PreviewUserPin extends StatelessWidget {
  const _PreviewUserPin();

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            color: AppColors.info,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.white, width: 4),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 9)
            ]),
      );
}

class _NearbyMapPainter extends CustomPainter {
  const _NearbyMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFEDEEEA), BlendMode.src);
    final park = Paint()..color = const Color(0xFFDCE8D4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(size.width * .58, 120, 190, 170),
            const Radius.circular(34)),
        park);
    final block = Paint()..color = const Color(0xFFE1E2DD);
    for (final rect in const [
      Rect.fromLTWH(18, 136, 90, 58),
      Rect.fromLTWH(126, 158, 68, 82),
      Rect.fromLTWH(28, 315, 115, 72),
      Rect.fromLTWH(275, 360, 105, 74),
      Rect.fromLTWH(94, 505, 104, 68),
      Rect.fromLTWH(250, 565, 126, 78),
    ]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(9)), block);
    }
    final edge = Paint()
      ..color = const Color(0xFFD3D4CF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    final road = Paint()
      ..color = AppColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    final roads = [
      Path()
        ..moveTo(-20, 260)
        ..cubicTo(100, 225, 225, 240, size.width + 20, 188),
      Path()
        ..moveTo(205, 90)
        ..cubicTo(190, 250, 260, 390, 225, size.height + 20),
      Path()
        ..moveTo(-20, 480)
        ..cubicTo(120, 430, 280, 500, size.width + 20, 450),
      Path()
        ..moveTo(20, size.height + 10)
        ..cubicTo(105, 650, 150, 580, 430, 560),
    ];
    for (final path in roads) {
      canvas.drawPath(path, edge);
      canvas.drawPath(path, road);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Kept as a reference screen for direct store detail design reviews.
// ignore: unused_element
class _RestaurantPreview extends StatelessWidget {
  const _RestaurantPreview();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 210,
            pinned: true,
            leading: _RoundIcon(icon: Icons.arrow_back_rounded, onTap: () {}),
            actions: const [
              _RoundIcon(icon: Icons.favorite_border_rounded),
              _RoundIcon(icon: Icons.ios_share_rounded),
              SizedBox(width: 6),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: const Color(0xFFFFC9C9),
                alignment: Alignment.center,
                child: const Text('🍜', style: TextStyle(fontSize: 104)),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Noodle Social',
                      style: AppTextStyles.headlineLarge),
                  const SizedBox(height: 5),
                  Text('Asian · Noodles · 1.2 mi',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      _InfoPill(label: '4.7 ★', detail: '500+ ratings'),
                      SizedBox(width: 8),
                      _InfoPill(label: '20–30 min', detail: 'Delivery time'),
                      SizedBox(width: 8),
                      _InfoPill(label: '\$0', detail: 'Delivery fee'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.accentSurface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(children: [
                      Icon(Icons.local_offer_rounded, size: 19),
                      SizedBox(width: 9),
                      Expanded(
                          child: Text('20% off orders over \$18',
                              style: AppTextStyles.titleSmall)),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  const Text('Popular items', style: AppTextStyles.titleLarge),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate(const [
              _MenuRow(
                  emoji: '🍜',
                  name: 'Firecracker noodles',
                  description:
                      'Wok noodles, chili crisp, scallions and sesame.',
                  price: '\$12.90'),
              _MenuRow(
                  emoji: '🥟',
                  name: 'Crispy chicken dumplings',
                  description: 'Six golden dumplings with house dipping sauce.',
                  price: '\$8.50'),
              _MenuRow(
                  emoji: '🍚',
                  name: 'Teriyaki rice bowl',
                  description: 'Grilled chicken, vegetables and steamed rice.',
                  price: '\$11.75'),
              SizedBox(height: 118),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
              height: 54,
              child: _DarkPill(label: 'View cart · 2 items · \$21.40')),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(
      {required this.emoji,
      required this.name,
      required this.description,
      required this.price});
  final String emoji;
  final String name;
  final String description;
  final String price;
  @override
  Widget build(BuildContext context) => Container(
        height: 140,
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTextStyles.titleMedium),
                    const SizedBox(height: 5),
                    Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                    const Spacer(),
                    Text(price, style: AppTextStyles.titleSmall),
                  ],
                ),
              ),
            ),
            Container(
              width: 122,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE2C9),
                borderRadius:
                    BorderRadius.horizontal(right: Radius.circular(17)),
              ),
              child: Stack(
                children: [
                  Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 58))),
                  const Positioned(
                    right: 9,
                    bottom: 9,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white,
                      child:
                          Icon(Icons.add_rounded, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SearchPreview extends StatelessWidget {
  const _SearchPreview();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 118),
            children: [
              const Text('Search', style: AppTextStyles.headlineLarge),
              const SizedBox(height: 14),
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  const Icon(Icons.search_rounded, size: 23),
                  const SizedBox(width: 10),
                  Text('Food, groceries, drinks…',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                ]),
              ),
              const SizedBox(height: 26),
              const Text('Popular right now', style: AppTextStyles.titleMedium),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SearchCategory(
                      icon: Icons.local_pizza_rounded, label: 'Pizza'),
                  _SearchCategory(
                      icon: Icons.lunch_dining_rounded, label: 'Burgers'),
                  _SearchCategory(
                      icon: Icons.ramen_dining_rounded, label: 'Asian'),
                  _SearchCategory(
                      icon: Icons.local_cafe_rounded, label: 'Coffee'),
                  _SearchCategory(
                      icon: Icons.icecream_rounded, label: 'Desserts'),
                  _SearchCategory(
                      icon: Icons.local_bar_rounded, label: 'Drinks'),
                ],
              ),
              const SizedBox(height: 28),
              const Text('Explore nearby', style: AppTextStyles.titleMedium),
              const SizedBox(height: 12),
              const _SearchStoreRow(
                  icon: Icons.ramen_dining_rounded,
                  name: 'Noodle Social',
                  meta: '20–30 min · 4.8'),
              const _SearchStoreRow(
                  icon: Icons.lunch_dining_rounded,
                  name: 'Smash Yard',
                  meta: '25–35 min · 4.7'),
              const _SearchStoreRow(
                  icon: Icons.local_grocery_store_rounded,
                  name: 'Fresh Market',
                  meta: '15–25 min · 4.9'),
            ],
          ),
        ),
      );
}

class _SearchCategory extends StatelessWidget {
  const _SearchCategory({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        width: (MediaQuery.sizeOf(context).width - 56) / 3,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Icon(icon, size: 27),
          const SizedBox(height: 7),
          Text(label, style: AppTextStyles.labelSmall),
        ]),
      );
}

class _SearchStoreRow extends StatelessWidget {
  const _SearchStoreRow(
      {required this.icon, required this.name, required this.meta});
  final IconData icon;
  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppSurface(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: AppColors.accentSurface,
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 23)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name, style: AppTextStyles.titleSmall),
                  const SizedBox(height: 3),
                  Text(meta,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ])),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      );
}

// Kept as a reference screen for direct cart design reviews.
// ignore: unused_element
class _CartPreview extends StatelessWidget {
  const _CartPreview();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AppSurface(
            color: AppColors.brandGreenSurface,
            child: Row(children: [
              Icon(Icons.location_on_rounded, color: AppColors.brandGreen),
              SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Deliver to', style: AppTextStyles.bodySmall),
                  Text('18 Willow Avenue', style: AppTextStyles.titleSmall),
                ],
              )),
              Text('Change', style: AppTextStyles.labelLarge),
            ]),
          ),
          const SizedBox(height: 14),
          AppSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.ramen_dining_rounded, size: 28),
                    SizedBox(width: 10),
                    Text('Noodle Social', style: AppTextStyles.titleMedium),
                  ]),
                ),
                const Divider(),
                const _CartRow(
                    name: 'Firecracker noodles', price: '\$12.90', qty: 1),
                const _CartRow(
                    name: 'Chicken dumplings', price: '\$8.50', qty: 1),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal'),
                        Text('\$21.40', style: AppTextStyles.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                          onPressed: () {},
                          child: const Text('Go to checkout')),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const AppSurface(
            child: Row(children: [
              Icon(Icons.add_circle_outline_rounded),
              SizedBox(width: 10),
              Text('Add items', style: AppTextStyles.titleSmall),
              Spacer(),
              Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.name, required this.price, required this.qty});
  final String name;
  final String price;
  final int qty;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.restaurant_rounded, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(name, style: AppTextStyles.titleSmall)),
          Column(children: [
            Text(price, style: AppTextStyles.titleSmall),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(999)),
              child: Text('−  $qty  +', style: AppTextStyles.labelSmall),
            ),
          ]),
        ]),
      );
}

class _OrdersPreview extends StatelessWidget {
  const _OrdersPreview();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 118),
            children: [
              const AppPageTitle(
                  eyebrow: 'Your activity',
                  title: 'Orders',
                  subtitle:
                      'Track what is arriving and quickly reorder favourites.'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16)),
                  child: const Row(children: [
                    Expanded(child: _SelectedTab(label: 'Active')),
                    Expanded(child: Center(child: Text('Past'))),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _MockLiveJourneyMap(),
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  const Expanded(
                      child: Text('Your active orders',
                          style: AppTextStyles.titleMedium)),
                  Text('Tap to switch map',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ]),
              ),
              const SizedBox(height: 10),
              const _MockOrder(
                  icon: Icons.delivery_dining_rounded,
                  color: AppColors.info,
                  surface: Color(0xFFEAF2FF),
                  title: 'On the way',
                  detail: 'Your courier has the order',
                  items: '1× Firecracker noodles · 1× Dumplings',
                  total: '\$24.90',
                  selected: true),
              const _MockOrder(
                  icon: Icons.restaurant_rounded,
                  color: AppColors.brandGreen,
                  surface: AppColors.brandGreenSurface,
                  title: 'Being prepared',
                  detail: 'Your order is in the kitchen',
                  items: '2× Classic smash burger · 1× Fries',
                  total: '\$29.40'),
            ],
          ),
        ),
      );
}

class _MockOrder extends StatelessWidget {
  const _MockOrder(
      {required this.icon,
      required this.color,
      required this.surface,
      required this.title,
      required this.detail,
      required this.items,
      required this.total,
      this.selected = false});
  final IconData icon;
  final Color color;
  final Color surface;
  final String title;
  final String detail;
  final String items;
  final String total;
  final bool selected;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: AppSurface(
          color: selected ? AppColors.primarySurface : AppColors.surface,
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: surface, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleSmall)),
                      const SizedBox(width: 7),
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle)),
                    ]),
                    const SizedBox(height: 3),
                    Text(items,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 5),
                    Text(detail,
                        style: AppTextStyles.labelSmall.copyWith(
                            color: color, fontWeight: FontWeight.w700)),
                  ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(total, style: AppTextStyles.labelLarge),
              const SizedBox(height: 10),
              Icon(selected ? Icons.map_rounded : Icons.chevron_right_rounded,
                  size: 20,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textTertiary),
            ]),
          ]),
        ),
      );
}

class _MockLiveJourneyMap extends StatelessWidget {
  const _MockLiveJourneyMap();

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 306,
          child: Stack(children: [
            const Positioned.fill(
                child: CustomPaint(painter: _MockMapPainter())),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                    color: AppColors.selectedDark,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(color: Color(0x26000000), blurRadius: 14)
                    ]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: AppColors.accent, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text('LIVE GPS',
                      style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
            const Positioned(
                top: 82,
                left: 196,
                child: _PreviewMapMarker(
                    icon: Icons.delivery_dining_rounded,
                    background: AppColors.selectedDark,
                    foreground: AppColors.white,
                    size: 48)),
            const Positioned(
                top: 150,
                right: 50,
                child: _PreviewMapMarker(
                    icon: Icons.home_rounded,
                    background: AppColors.accent,
                    foreground: AppColors.textPrimary,
                    size: 40)),
            const Positioned(
                top: 62,
                left: 58,
                child: _PreviewMapMarker(
                    icon: Icons.storefront_rounded,
                    background: AppColors.white,
                    foreground: AppColors.textPrimary,
                    size: 36)),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
                decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x28000000),
                          blurRadius: 16,
                          offset: Offset(0, 5))
                    ]),
                child: Row(children: [
                  Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.delivery_dining_rounded,
                          color: AppColors.info, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your order is on the way',
                              style: AppTextStyles.titleSmall),
                          const SizedBox(height: 2),
                          Text('Tariro is sharing a live location',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textSecondary)),
                        ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 22),
                ]),
              ),
            ),
          ]),
        ),
      );
}

class _PreviewMapMarker extends StatelessWidget {
  const _PreviewMapMarker(
      {required this.icon,
      required this.background,
      required this.foreground,
      required this.size});
  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x35000000),
                  blurRadius: 10,
                  offset: Offset(0, 3))
            ]),
        child: Icon(icon, color: foreground, size: size * .5),
      );
}

class _MockMapPainter extends CustomPainter {
  const _MockMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFEDEEEA), BlendMode.src);
    final park = Paint()..color = const Color(0xFFDDE8D5);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(size.width * .67, -18, 125, 112),
            const Radius.circular(28)),
        park);
    final buildings = Paint()..color = const Color(0xFFE2E2DE);
    for (final rect in const [
      Rect.fromLTWH(18, 24, 72, 34),
      Rect.fromLTWH(114, 30, 60, 45),
      Rect.fromLTWH(28, 130, 88, 52),
      Rect.fromLTWH(265, 114, 92, 44),
      Rect.fromLTWH(138, 188, 70, 42),
    ]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(7)), buildings);
    }
    final roadEdge = Paint()
      ..color = const Color(0xFFD5D6D1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    final road = Paint()
      ..color = AppColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    final paths = [
      Path()
        ..moveTo(-10, 98)
        ..cubicTo(90, 102, 145, 100, size.width + 12, 52),
      Path()
        ..moveTo(172, -10)
        ..cubicTo(178, 70, 214, 122, 238, size.height + 10),
      Path()
        ..moveTo(-10, 224)
        ..cubicTo(90, 204, 250, 220, size.width + 12, 184),
    ];
    for (final path in paths) {
      canvas.drawPath(path, roadEdge);
      canvas.drawPath(path, road);
    }
    final route = Paint()
      ..color = AppColors.selectedDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(82, 80)
          ..cubicTo(132, 91, 178, 102, 216, 109)
          ..cubicTo(264, 122, 292, 145, size.width - 70, 170),
        route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AccountPreview extends StatelessWidget {
  const _AccountPreview();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 118),
            children: [
              const AppPageTitle(
                  eyebrow: 'Your Zvingo',
                  title: 'Account',
                  subtitle:
                      'Personal details, payments, addresses and support.'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppSurface(
                  color: AppColors.selectedDark,
                  child: Row(children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(19)),
                      child: const Icon(Icons.person_rounded, size: 30),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tinashe M.',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800)),
                          SizedBox(height: 4),
                          Text('tinashe@example.com',
                              style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_outlined, color: Colors.white),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppSurface(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(children: [
                    AppIconTile(
                        icon: Icons.person_outline_rounded,
                        title: 'Manage account',
                        subtitle: 'Name, email and phone',
                        onTap: () {}),
                    const Divider(indent: 70),
                    AppIconTile(
                        icon: Icons.credit_card_rounded,
                        title: 'Payment methods',
                        onTap: () {}),
                    const Divider(indent: 70),
                    AppIconTile(
                        icon: Icons.location_on_outlined,
                        title: 'Saved addresses',
                        onTap: () {}),
                    const Divider(indent: 70),
                    AppIconTile(
                        icon: Icons.favorite_border_rounded,
                        title: 'Saved stores',
                        onTap: () {}),
                    const Divider(indent: 70),
                    AppIconTile(
                        icon: Icons.help_outline_rounded,
                        title: 'Help and support',
                        onTap: () {}),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );
}

class _SelectedTab extends StatelessWidget {
  const _SelectedTab({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: AppColors.selectedDark,
            borderRadius: BorderRadius.circular(13)),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      );
}

class _DarkPill extends StatelessWidget {
  const _DarkPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.selectedDark,
            borderRadius: BorderRadius.circular(14)),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      );
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.detail});
  final String label;
  final String detail;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 9, color: AppColors.textSecondary)),
          ]),
        ),
      );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: CircleAvatar(
          backgroundColor: Colors.white,
          child: IconButton(
              onPressed: onTap, icon: Icon(icon, color: AppColors.textPrimary)),
        ),
      );
}
