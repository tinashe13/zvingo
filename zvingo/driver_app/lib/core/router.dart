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
    ],
  );
});
