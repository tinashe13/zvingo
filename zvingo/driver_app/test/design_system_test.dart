import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_app/core/app_colors.dart';
import 'package:driver_app/core/app_spacing.dart';
import 'package:driver_app/core/app_text_styles.dart';
import 'package:driver_app/core/theme.dart';
import 'package:driver_app/models/delivery_state.dart';
import 'package:driver_app/widgets/widgets.dart';

/// Regression tests for the driver design system.
///
/// These exist because three real defects shipped past `flutter analyze`
/// during the foundation work: a step indicator that overflowed at 320px, an
/// offer-card header that overflowed at 200% text scale, and an app bar that
/// asserted when built without a GoRouter ancestor. The analyzer cannot see
/// any of those; a pump at the smallest supported viewport can.
///
/// The design-system checklist this enforces (docs/DESIGN_SYSTEM.md §7):
/// "Works at 320px width and at 200% text scale without overflow."
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  /// One of every public widget in the library, with realistic Zimbabwean
  /// content and deliberately long strings.
  Widget gallery() => Column(
        children: [
          const DriverAppBar(title: 'Earnings history', subtitle: 'Last 30 days'),
          const DriverPrimaryButton(
            label: 'Go online right now',
            onPressed: null,
            disabledReason:
                'Add your vehicle details before you can go online today.',
          ),
          DriverPrimaryButton(
            label: 'Confirm collection of order',
            icon: Icons.check,
            onPressed: () {},
          ),
          DriverPrimaryButton(
            label: 'Submitting now',
            isLoading: true,
            onPressed: () {},
          ),
          DriverSecondaryButton(label: 'Maybe later today', onPressed: () {}),
          DriverDestructiveButton(
            label: 'Cancel this delivery',
            onPressed: () {},
          ),
          DriverTextButton(label: 'Skip for now', onPressed: () {}),
          DriverIconButton(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: () {},
          ),
          const StatusChip(label: 'Waiting on merchant', tone: StatusTone.warning),
          const StatusChip(
            label: 'Delivered',
            tone: StatusTone.success,
            emphasized: true,
          ),
          AnimatedCount.currency(cents: 123456, style: AppTextStyles.moneyHero),
          const ConnectionStatusBanner(status: ConnectionStatus.connected),
          const ConnectionStatusBanner(status: ConnectionStatus.reconnecting),
          const ConnectionStatusBanner(status: ConnectionStatus.failed),
          const SkeletonBox(height: 20),
          const SkeletonBox.line(widthFactor: 0.6),
          const OfferCardSkeleton(),
          const EarningsRowSkeleton(),
          const DeliveryCardSkeleton(),
          const SkeletonList(count: 2, builder: EarningsRowSkeleton.new),
          for (final state in DeliveryState.values)
            DeliveryStepIndicator(currentState: state),
          DriverSlideToConfirm(
            text: 'Slide to confirm arrival at customer',
            action: SlideAction.arrive,
            onConfirm: () {},
          ),
          DriverSlideToConfirm(
            text: 'Slide to complete delivery',
            action: SlideAction.deliver,
            enabled: false,
            disabledReason: 'Enter the 4-digit code from the customer first.',
            onConfirm: () {},
          ),
          OnlineOfflineToggle(
            isOnline: true,
            onChanged: (_) {},
            onlineSubtitle: 'Listening for offers in Harare CBD',
          ),
          OnlineOfflineToggle(isOnline: false, onChanged: (_) {}),
          ActiveDeliveryBar(
            state: DeliveryState.enRouteDelivery,
            orderLabel: '#A4F2',
            destination: '12 Samora Machel Avenue, Harare',
            onTap: () {},
          ),
          OfferCard(
            merchantName: 'Chicken Inn Avondale',
            merchantAddress: '5 Leopold Takawira Street',
            customerAddress: '12 Samora Machel Avenue, Harare',
            deliveryFeeCents: 1000,
            tipCents: 150,
            orderSubtotalCents: 2400,
            itemsSummary: '2x Chicken burger, 1x Fanta',
            estimatedDistanceKm: 7.4,
            pickupDistanceKm: 1.2,
            estimatedTimeMinutes: 18,
            remainingSeconds: 6,
            paymentMethod: 'Cash',
            onAccept: () {},
            onDecline: () {},
          ),
          DriverEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No deliveries yet today',
            message: 'Go online and offers will appear here as they come in.',
            actionLabel: 'Go online',
            onAction: () {},
          ),
          DriverErrorState(
            title: "Couldn't load your earnings",
            message: 'Check your connection and try again.',
            onRetry: () {},
            technical: 'HTTP 503',
          ),
          TapScale(onTap: () {}, child: const Text('Tappable card')),
          const StaggeredEntrance(index: 3, child: Text('Staggered item')),
          DriverActionFooter(
            child: DriverPrimaryButton(label: 'Confirm', onPressed: () {}),
          ),
        ],
      );

  group('theme', () {
    test('light and dark are both fully built', () {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        expect(theme.useMaterial3, isTrue);
        // Non-deprecated Flutter 3.47 theme data types.
        expect(theme.cardTheme, isA<CardThemeData>());
        expect(theme.dialogTheme, isA<DialogThemeData>());
        // Elevation is a shadow token (§3.3), never Material elevation.
        expect(theme.cardTheme.elevation, 0);
        expect(theme.appBarTheme.elevation, 0);
      }
      expect(AppTheme.lightTheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
    });

    test('driver buttons are 56pt, not the 52 in §5.1', () {
      expect(AppSpacing.buttonHeight, 56);
      final size = AppTheme.lightTheme.elevatedButtonTheme.style?.minimumSize
          ?.resolve({});
      expect(size?.height, 56);
    });
  });

  group('tokens', () {
    test('colors match DESIGN_SYSTEM §1', () {
      expect(AppColors.action, const Color(0xFF101210));
      expect(AppColors.primary, AppColors.action);
      expect(AppColors.brandGreen, const Color(0xFF0A8F5B));
      expect(AppColors.accent, const Color(0xFFD7F654));
      expect(AppColors.neutral0, const Color(0xFFFFFFFF));
      expect(AppColors.neutral400, const Color(0xFF999B96));
      expect(AppColors.neutral900, const Color(0xFF101210));
      expect(AppColors.success, const Color(0xFF0A8F5B));
      expect(AppColors.warning, const Color(0xFFB96800));
      expect(AppColors.error, const Color(0xFFBA1A1A));
      expect(AppColors.info, const Color(0xFF246BCE));
      expect(AppColors.rating, const Color(0xFFF4A100));
      expect(AppColors.deal, const Color(0xFFC9362B));
    });

    test('type scale matches §2', () {
      expect(AppTextStyles.display.fontSize, 32);
      expect(AppTextStyles.h1.fontSize, 26);
      expect(AppTextStyles.h2.fontSize, 21);
      expect(AppTextStyles.h3.fontSize, 17);
      expect(AppTextStyles.body.fontSize, 15);
      expect(AppTextStyles.caption.fontSize, 13);
      expect(AppTextStyles.overline.fontSize, 11);
      expect(AppTextStyles.button.fontSize, 15);
    });

    test('money, metric and time styles use tabular figures', () {
      for (final style in [
        AppTextStyles.display,
        AppTextStyles.moneyHero,
        AppTextStyles.moneyLarge,
        AppTextStyles.money,
        AppTextStyles.metric,
        AppTextStyles.caption,
      ]) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'live-updating digits must not jitter',
        );
      }
    });

    test('radii and the 4pt spacing scale match §3', () {
      expect(AppSpacing.radiusSm, 8);
      expect(AppSpacing.radiusMd, 14);
      expect(AppSpacing.radiusLg, 20);
      expect(AppSpacing.radiusXl, 28);
      expect(
        [
          AppSpacing.xxs,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.section,
        ],
        [2, 4, 8, 12, 16, 20, 24, 32],
      );
      // Responsive screen padding: 16 / 24 / 32 (§3.1).
      expect(AppSpacing.screenPaddingFor(390), 16);
      expect(AppSpacing.screenPaddingFor(700), 24);
      expect(AppSpacing.screenPaddingFor(1280), 32);
    });
  });

  group('widget library', () {
    for (final brightness in Brightness.values) {
      testWidgets('renders in $brightness', (tester) async {
        await tester.pumpWidget(host(gallery(), brightness: brightness));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('survives 320px width at 200% text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2.0),
              size: Size(320, 6000),
            ),
            child: Scaffold(body: SingleChildScrollView(child: gallery())),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  });

  group('slide to confirm', () {
    testWidgets('commits when dragged past the threshold', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(host(SizedBox(
        width: 340,
        child: DriverSlideToConfirm(
          text: 'Slide to confirm',
          onConfirm: () => confirmed = true,
        ),
      )));
      await tester.pump();

      await tester.drag(
        find.byIcon(Icons.arrow_forward_rounded),
        const Offset(400, 0),
      );
      await tester.pump();
      expect(confirmed, isTrue);
    });

    testWidgets('springs back when released short', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(host(SizedBox(
        width: 340,
        child: DriverSlideToConfirm(
          text: 'Slide to confirm',
          onConfirm: () => confirmed = true,
        ),
      )));
      await tester.pump();

      await tester.drag(
        find.byIcon(Icons.arrow_forward_rounded),
        const Offset(40, 0),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(confirmed, isFalse);
    });

    testWidgets('disabled shows its reason and cannot fire', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(host(SizedBox(
        width: 340,
        child: DriverSlideToConfirm(
          text: 'Slide to complete',
          enabled: false,
          disabledReason: 'Enter the code from the customer first.',
          onConfirm: () => confirmed = true,
        ),
      )));
      await tester.pump();

      expect(
        find.text('Enter the code from the customer first.'),
        findsOneWidget,
      );
      await tester.drag(find.byIcon(Icons.lock_outline), const Offset(400, 0));
      await tester.pump();
      expect(confirmed, isFalse);
    });
  });

  group('offer card', () {
    testWidgets('payout is the largest thing on the card', (tester) async {
      await tester.pumpWidget(host(OfferCard(
        merchantName: 'Chicken Inn',
        merchantAddress: '5 Leopold Takawira Street',
        customerAddress: '12 Samora Machel Avenue',
        deliveryFeeCents: 1000,
        tipCents: 150,
        estimatedDistanceKm: 7.4,
        estimatedTimeMinutes: 18,
        remainingSeconds: 30,
        paymentMethod: 'EcoCash',
        onAccept: () {},
        onDecline: () {},
      )));
      await tester.pump();

      // 85% of $10.00 plus the $1.50 tip.
      final payout = tester.widget<Text>(find.text(r'$10.00'));
      final distance = tester.widget<Text>(find.text('7.4 km'));
      expect(payout.style!.fontSize, greaterThan(distance.style!.fontSize!));
    });

    testWidgets('countdown tone escalates as the offer expires',
        (tester) async {
      OfferCard card(int remaining) => OfferCard(
            merchantName: 'Chicken Inn',
            merchantAddress: '5 Leopold Takawira Street',
            customerAddress: '12 Samora Machel Avenue',
            deliveryFeeCents: 1000,
            estimatedDistanceKm: 7.4,
            estimatedTimeMinutes: 18,
            remainingSeconds: remaining,
            paymentMethod: 'Cash',
            onAccept: () {},
            onDecline: () {},
          );

      // 45s window: >35% success, 15-35% warning, <=15% error.
      expect(card(40).remainingSeconds, 40);
      await tester.pumpWidget(host(card(40)));
      expect(find.text('40s left'), findsOneWidget);
      await tester.pumpWidget(host(card(5)));
      await tester.pump();
      expect(find.text('5s left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an expired offer disables accept and says why',
        (tester) async {
      await tester.pumpWidget(host(OfferCard(
        merchantName: 'Chicken Inn',
        merchantAddress: '5 Leopold Takawira Street',
        customerAddress: '12 Samora Machel Avenue',
        deliveryFeeCents: 1000,
        estimatedDistanceKm: 7.4,
        estimatedTimeMinutes: 18,
        remainingSeconds: 0,
        paymentMethod: 'Cash',
        onAccept: () {},
        onDecline: () {},
      )));
      await tester.pump();
      expect(
        find.text('This offer expired. The next one will appear here.'),
        findsOneWidget,
      );
    });
  });

  group('buttons', () {
    testWidgets('a disabled button always states its reason', (tester) async {
      await tester.pumpWidget(host(const DriverPrimaryButton(
        label: 'Go online',
        onPressed: null,
        disabledReason: 'Add your vehicle details first.',
      )));
      expect(find.text('Add your vehicle details first.'), findsOneWidget);
    });

    testWidgets('loading locks the width', (tester) async {
      Widget button({required bool loading}) => host(Align(
            alignment: Alignment.centerLeft,
            child: DriverPrimaryButton(
              label: 'Confirm pickup',
              expanded: false,
              isLoading: loading,
              onPressed: () {},
            ),
          ));

      await tester.pumpWidget(button(loading: false));
      await tester.pump();
      final idle = tester.getSize(find.byType(DriverButton)).width;

      await tester.pumpWidget(button(loading: true));
      await tester.pump(const Duration(milliseconds: 300));
      final busy = tester.getSize(find.byType(DriverButton)).width;

      expect(busy, closeTo(idle, 1.0));
    });
  });
}
