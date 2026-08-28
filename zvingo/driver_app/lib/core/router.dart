import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../features/auth/login_screen.dart';
import '../features/shell/main_shell.dart';
import '../features/home/home_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/earnings/earnings_screen.dart';
import '../features/earnings/earnings_history_screen.dart';
import '../features/ratings/ratings_screen.dart';
import '../features/account/account_screen.dart';
import '../features/account/vehicle_details_screen.dart';
import '../features/account/info_screen.dart';
import '../features/delivery/offer_screen.dart';
import '../features/delivery/navigate_to_merchant_screen.dart';
import '../features/delivery/at_merchant_screen.dart';
import '../features/delivery/confirm_pickup_screen.dart';
import '../features/delivery/navigate_to_customer_screen.dart';
import '../features/delivery/at_customer_screen.dart';
import '../features/delivery/complete_delivery_screen.dart';

/// Router configuration — mirrors Screen.kt + ZvingoNavHost.kt.
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final isLoggingIn = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoggingIn) return '/login';
      if (isLoggedIn && isLoggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      // Main shell with bottom nav
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/schedule',
            builder: (context, state) => const ScheduleScreen(),
          ),
          GoRoute(
            path: '/earnings',
            builder: (context, state) => const EarningsScreen(),
          ),
          GoRoute(
            path: '/ratings',
            builder: (context, state) => const RatingsScreen(),
          ),
          GoRoute(
            path: '/account',
            builder: (context, state) => const AccountScreen(),
          ),
        ],
      ),
      // Delivery flow (no bottom nav — outside shell)
      GoRoute(
        path: '/delivery/offer',
        builder: (context, state) => const OfferScreen(),
      ),
      GoRoute(
        path: '/delivery/navigate-to-merchant',
        builder: (context, state) => const NavigateToMerchantScreen(),
      ),
      GoRoute(
        path: '/delivery/at-merchant',
        builder: (context, state) => const AtMerchantScreen(),
      ),
      GoRoute(
        path: '/delivery/confirm-pickup',
        builder: (context, state) => const ConfirmPickupScreen(),
      ),
      GoRoute(
        path: '/delivery/navigate-to-customer',
        builder: (context, state) => const NavigateToCustomerScreen(),
      ),
      GoRoute(
        path: '/delivery/at-customer',
        builder: (context, state) => const AtCustomerScreen(),
      ),
      GoRoute(
        path: '/delivery/complete',
        builder: (context, state) => const CompleteDeliveryScreen(),
      ),
      // Earnings history (full reconciliation)
      GoRoute(
        path: '/earnings/history',
        builder: (context, state) => const EarningsHistoryScreen(),
      ),
      // Vehicle details
      GoRoute(
        path: '/vehicle',
        builder: (context, state) => const VehicleDetailsScreen(),
      ),
      // Account info screens
      GoRoute(
        path: '/account/notifications',
        builder: (context, state) => const InfoScreen(
          title: 'Notifications',
          icon: Icons.notifications_outlined,
          paragraphs: [
            'Stay up to date with delivery offers, earnings summaries, and important account alerts.',
            'You can manage notification preferences from your device settings once push notifications are enabled for your account.',
          ],
        ),
      ),
      GoRoute(
        path: '/account/safety',
        builder: (context, state) => const InfoScreen(
          title: 'Safety',
          icon: Icons.shield_outlined,
          paragraphs: [
            'Your safety is our priority. Keep your vehicle maintained and follow local traffic laws at all times.',
            'If you ever feel unsafe during a delivery, pull over to a secure location and contact support immediately.',
          ],
        ),
      ),
      GoRoute(
        path: '/account/help',
        builder: (context, state) => const InfoScreen(
          title: 'Help',
          icon: Icons.help_outline,
          paragraphs: [
            'Need assistance? Check the frequently asked questions below or reach out to our driver support team.',
            'For urgent delivery issues, contact support through the in-app chat or call our 24/7 driver helpline.',
          ],
        ),
      ),
      GoRoute(
        path: '/account/about',
        builder: (context, state) => const InfoScreen(
          title: 'About',
          icon: Icons.info_outline,
          paragraphs: [
            'Zvingo Driver',
            'Version 1.0.0',
            'Zvingo connects local drivers with merchants and customers for fast, reliable delivery.',
          ],
        ),
      ),
      GoRoute(
        path: '/account/terms',
        builder: (context, state) => const InfoScreen(
          title: 'Terms of Service',
          icon: Icons.description_outlined,
          paragraphs: [
            'By using the Zvingo Driver app, you agree to complete deliveries in accordance with local laws and platform policies.',
            'Drivers are independent contractors responsible for their own vehicle, insurance, and tax obligations.',
          ],
        ),
      ),
      GoRoute(
        path: '/account/privacy',
        builder: (context, state) => const InfoScreen(
          title: 'Privacy Policy',
          icon: Icons.privacy_tip_outlined,
          paragraphs: [
            'We collect only the information needed to provide delivery services, including your location and account details.',
            'Your data is never sold to third parties and is handled in accordance with applicable privacy laws.',
          ],
        ),
      ),
    ],
  );
});
