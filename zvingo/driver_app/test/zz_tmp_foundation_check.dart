import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/core/theme.dart';
import 'package:driver_app/core/app_colors.dart';
import 'package:driver_app/models/delivery_state.dart';
import 'package:driver_app/widgets/widgets.dart';

Widget host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    home: Scaffold(body: Center(child: SingleChildScrollView(child: child))),
  );
}

void main() {
  for (final b in Brightness.values) {
    testWidgets('theme builds ($b)', (t) async {
      final theme = b == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme;
      expect(theme.colorScheme.brightness, b);
      expect(theme.cardTheme, isA<CardThemeData>());
    });

    testWidgets('widget library renders ($b)', (t) async {
      await t.pumpWidget(host(Column(children: [
        const DriverPrimaryButton(label: 'Go online', onPressed: null,
            disabledReason: 'Set your vehicle details first.'),
        DriverPrimaryButton(label: 'Go online', onPressed: () {}),
        DriverSecondaryButton(label: 'Later', onPressed: () {}),
        DriverDestructiveButton(label: 'Cancel', onPressed: () {}),
        DriverTextButton(label: 'Skip', onPressed: () {}),
        DriverPrimaryButton(label: 'Submitting', isLoading: true, onPressed: () {}),
        DriverIconButton(icon: Icons.close, tooltip: 'Close', onPressed: () {}),
        const StatusChip(label: 'Online', tone: StatusTone.success),
        const StatusChip(label: 'Cash', tone: StatusTone.warning, emphasized: true),
        AnimatedCount.currency(cents: 2365),
        const ConnectionStatusBanner(status: ConnectionStatus.reconnecting),
        const ConnectionStatusBanner(status: ConnectionStatus.connected),
        const SkeletonBox(height: 20),
        const OfferCardSkeleton(),
        const EarningsRowSkeleton(),
        const DeliveryCardSkeleton(),
        const SkeletonList(count: 2, builder: EarningsRowSkeleton.new),
        const DeliveryStepIndicator(currentState: DeliveryState.pickedUp),
        DriverSlideToConfirm(text: 'Slide to confirm', onConfirm: () {}),
        DriverSlideToConfirm(text: 'Slide to deliver', action: SlideAction.deliver,
            enabled: false, disabledReason: 'Enter the code first.', onConfirm: () {}),
        OnlineOfflineToggle(isOnline: true, onChanged: (_) {}),
        OnlineOfflineToggle(isOnline: false, onChanged: (_) {}),
        ActiveDeliveryBar(state: DeliveryState.enRouteDelivery, orderLabel: '#A4F2',
            destination: '12 Samora Machel Ave', onTap: () {}),
        OfferCard(
          merchantName: 'Chicken Inn', merchantAddress: '5 Leopold Takawira St',
          customerAddress: '12 Samora Machel Ave', deliveryFeeCents: 1000,
          tipCents: 150, orderSubtotalCents: 2400, itemsSummary: '2x Burger',
          estimatedDistanceKm: 7.4, pickupDistanceKm: 1.2, estimatedTimeMinutes: 18,
          remainingSeconds: 6, totalSeconds: 45, paymentMethod: 'Cash',
          onAccept: () {}, onDecline: () {},
        ),
        DriverEmptyState(icon: Icons.inbox, title: 'No deliveries yet',
            message: 'Go online and offers appear here.', actionLabel: 'Go online',
            onAction: () {}),
        DriverErrorState(title: "Couldn't load earnings",
            message: 'Check your connection.', onRetry: () {}, technical: 'HTTP 503'),
        TapScale(onTap: () {}, child: const Text('tap me')),
        const StaggeredEntrance(index: 3, child: Text('staggered')),
      ]), brightness: b));
      await t.pump(const Duration(milliseconds: 300));
      expect(tester_ok(), true);
    });
  }

  testWidgets('slide-to-confirm commits past threshold', (t) async {
    var fired = false;
    await t.pumpWidget(host(SizedBox(width: 340,
        child: DriverSlideToConfirm(text: 'Slide', onConfirm: () => fired = true))));
    await t.pump();
    final thumb = find.byIcon(Icons.arrow_forward_rounded);
    expect(thumb, findsOneWidget);
    await t.drag(thumb, const Offset(400, 0));
    await t.pump();
    expect(fired, true);
  });

  testWidgets('slide-to-confirm springs back below threshold', (t) async {
    var fired = false;
    await t.pumpWidget(host(SizedBox(width: 340,
        child: DriverSlideToConfirm(text: 'Slide', onConfirm: () => fired = true))));
    await t.pump();
    await t.drag(find.byIcon(Icons.arrow_forward_rounded), const Offset(40, 0));
    await t.pump(const Duration(milliseconds: 400));
    expect(fired, false);
  });

  testWidgets('narrow screen and large text scale do not overflow', (t) async {
    t.view.physicalSize = const Size(320, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6), size: Size(320, 1400)),
        child: Scaffold(body: SingleChildScrollView(child: Column(children: [
          OfferCard(merchantName: 'Chicken Inn', merchantAddress: '5 Leopold Takawira St',
            customerAddress: '12 Samora Machel Ave', deliveryFeeCents: 1000, tipCents: 150,
            estimatedDistanceKm: 7.4, pickupDistanceKm: 1.2, estimatedTimeMinutes: 18,
            remainingSeconds: 30, paymentMethod: 'EcoCash', onAccept: () {}, onDecline: () {}),
          const DeliveryStepIndicator(currentState: DeliveryState.accepted),
          OnlineOfflineToggle(isOnline: true, onChanged: (_) {}),
        ]))),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    expect(tester_ok(), true);
  });

  test('tokens match DESIGN_SYSTEM §1', () {
    expect(AppColors.action, const Color(0xFF101210));
    expect(AppColors.brandGreen, const Color(0xFF0A8F5B));
    expect(AppColors.neutral400, const Color(0xFF999B96));
    expect(AppColors.warning, const Color(0xFFB96800));
    expect(AppColors.error, const Color(0xFFBA1A1A));
    expect(AppColors.info, const Color(0xFF246BCE));
    expect(AppColors.deal, const Color(0xFFC9362B));
  });
}

bool tester_ok() => true;
