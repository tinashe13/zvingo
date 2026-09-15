import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_screen.dart';
import '../features/account/info_screen.dart';
import '../features/account/vehicle_details_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/delivery/at_customer_screen.dart';
import '../features/delivery/at_merchant_screen.dart';
import '../features/delivery/complete_delivery_screen.dart';
import '../features/delivery/confirm_pickup_screen.dart';
import '../features/delivery/navigate_to_customer_screen.dart';
import '../features/delivery/navigate_to_merchant_screen.dart';
import '../features/delivery/offer_screen.dart';
import '../features/earnings/earnings_history_screen.dart';
import '../features/earnings/earnings_screen.dart';
import '../features/home/home_screen.dart';
import '../features/ratings/ratings_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/shell/main_shell.dart';
import '../models/delivery_state.dart';
import '../providers/auth_provider.dart';
import 'app_motion.dart';
import 'theme.dart';

// ── Route paths ──────────────────────────────────────────────────────────
//
// Referenced by name so a typo is a compile error rather than a silent
// navigation dead end.

/// Login.
const String routeLogin = '/login';

/// Tab: the dash map / home.
const String routeHome = '/';

/// Tab: schedule.
const String routeSchedule = '/schedule';

/// Tab: earnings.
const String routeEarnings = '/earnings';

/// Tab: ratings.
const String routeRatings = '/ratings';

/// Tab: account.
const String routeAccount = '/account';

/// Full earnings reconciliation list.
const String routeEarningsHistory = '/earnings/history';

/// Vehicle details form.
const String routeVehicle = '/vehicle';

/// Incoming offer.
const String routeOffer = '/delivery/offer';

/// Driving to the merchant.
const String routeNavigateToMerchant = '/delivery/navigate-to-merchant';

/// Waiting at the merchant.
const String routeAtMerchant = '/delivery/at-merchant';

/// Confirming what was collected.
const String routeConfirmPickup = '/delivery/confirm-pickup';

/// Driving to the customer.
const String routeNavigateToCustomer = '/delivery/navigate-to-customer';

/// Arrived at the customer.
const String routeAtCustomer = '/delivery/at-customer';

/// Handing over and closing out.
const String routeCompleteDelivery = '/delivery/complete';

/// The screen that belongs to a given point in the delivery state machine.
///
/// This is what the shell's persistent active-delivery bar taps into, so a
/// driver who wandered off to check their earnings lands back on exactly the
/// step they left — never on a generic delivery index.
String deliveryRouteFor(DeliveryState state) => switch (state) {
      DeliveryState.offered => routeOffer,
      DeliveryState.accepted ||
      DeliveryState.enRoutePickup =>
        routeNavigateToMerchant,
      DeliveryState.arrivedPickup => routeAtMerchant,
      DeliveryState.pickedUp => routeConfirmPickup,
      DeliveryState.enRouteDelivery => routeNavigateToCustomer,
      DeliveryState.arrivedDelivery => routeAtCustomer,
      DeliveryState.delivered => routeCompleteDelivery,
      DeliveryState.completed => routeHome,
    };

/// A page that slides in 24px from the right and fades over `motion/slow`
/// (§4.3). Back reverses it; reduced motion collapses it to a cross-fade.
CustomTransitionPage<void> _slidePage(
  GoRouterState state,
  Widget child, {
  String? name,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: name,
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.slow,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        ZvingoPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    ),
  );
}

/// A page that rises from the bottom like a sheet (§4.3 modal transition).
/// Used for the offer takeover, which interrupts whatever the driver is doing.
CustomTransitionPage<void> _sheetPage(
  GoRouterState state,
  Widget child, {
  String? name,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: name,
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.base,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = animation.drive(
        CurveTween(curve: AppMotion.curveOf(context, AppMotion.enter)),
      );
      if (AppMotion.reduced(context)) {
        return FadeTransition(opacity: curved, child: child);
      }
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// Tabs do not slide. Switching tab is a lateral move, not a push, and a
/// 400ms slide on every tab tap makes the app feel slow (§0.4).
NoTransitionPage<void> _tabPage(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

/// The app's `GoRouter`.
///
/// Auth gate: anything other than [routeLogin] redirects to login while
/// signed out, and login redirects to the dash once signed in.
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: routeHome,
    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final isLoggingIn = state.matchedLocation == routeLogin;

      if (!isLoggedIn && !isLoggingIn) return routeLogin;
      if (isLoggedIn && isLoggingIn) return routeHome;
      return null;
    },
    routes: [
      GoRoute(
        path: routeLogin,
        name: 'login',
        pageBuilder: (context, state) =>
            _slidePage(state, const LoginScreen(), name: 'login'),
      ),

      // ── Tabs ──────────────────────────────────────────────────────────
      //
      // `StatefulShellRoute.indexedStack` keeps every branch alive in an
      // IndexedStack, so each tab holds its scroll position, its filters and
      // any half-typed input while the driver hops between them. A driver who
      // checks their earnings mid-shift comes back to exactly the screen they
      // left.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: routeHome,
                name: 'home',
                pageBuilder: (context, state) =>
                    _tabPage(state, const HomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: routeSchedule,
                name: 'schedule',
                pageBuilder: (context, state) =>
                    _tabPage(state, const ScheduleScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: routeEarnings,
                name: 'earnings',
                pageBuilder: (context, state) =>
                    _tabPage(state, const EarningsScreen()),
                routes: [
                  GoRoute(
                    path: 'history',
                    name: 'earningsHistory',
                    pageBuilder: (context, state) =>
                        _slidePage(state, const EarningsHistoryScreen()),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: routeRatings,
                name: 'ratings',
                pageBuilder: (context, state) =>
                    _tabPage(state, const RatingsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: routeAccount,
                name: 'account',
                pageBuilder: (context, state) =>
                    _tabPage(state, const AccountScreen()),
                routes: [
                  GoRoute(
                    path: 'notifications',
                    name: 'accountNotifications',
                    pageBuilder: (context, state) => _slidePage(
                      state,
                      const InfoScreen(
                        title: 'Notifications',
                        icon: Icons.notifications_outlined,
                        paragraphs: [
                          'Stay up to date with delivery offers, earnings summaries, and important account alerts.',
                          'You can manage notification preferences from your device settings once push notifications are enabled for your account.',
                        ],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'safety',
                    name: 'accountSafety',
                    pageBuilder: (context, state) => _slidePage(
                      state,
                      const InfoScreen(
                        title: 'Safety',
                        icon: Icons.shield_outlined,
                        paragraphs: [
                          'Your safety is our priority. Keep your vehicle maintained and follow local traffic laws at all times.',
                          'If you ever feel unsafe during a delivery, pull over to a secure location and contact support immediately.',
                        ],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'help',
                    name: 'accountHelp',
                    pageBuilder: (context, state) => _slidePage(
                      state,
                      const InfoScreen(
                        title: 'Help',
                        icon: Icons.help_outline,
                        paragraphs: [
                          'Need assistance? Check the frequently asked questions below or reach out to our driver support team.',
                          'For urgent delivery issues, contact support through the in-app chat or call our 24/7 driver helpline.',
                        ],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'about',
                    name: 'accountAbout',
                    pageBuilder: (context, state) => _slidePage(
                      state,
                      const InfoScreen(
                        title: 'About',
                        icon: Icons.info_outline,
                        paragraphs: [
                          'Zvingo Driver',
                          'Version 1.0.0',
                          'Zvingo connects local drivers with merchants and customers for fast, reliable delivery.',
                        ],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'terms',
                    name: 'accountTerms',
                    pageBuilder: (context, state) => _slidePage(
                      state,
                      const InfoScreen(
                        title: 'Terms of Service',
                        icon: Icons.description_outlined,
                        paragraphs: [
                          'By using the Zvingo Driver app, you agree to complete deliveries in accordance with local laws and platform policies.',
                          'Drivers are independent contractors responsible for their own vehicle, insurance, and tax obligations.',
                        ],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'privacy',
                    name: 'accountPrivacy',
                    pageBuilder: (context, state) => _slidePage(
                      state,
                      const InfoScreen(
                        title: 'Privacy Policy',
                        icon: Icons.privacy_tip_outlined,
                        paragraphs: [
                          'We collect only the information needed to provide delivery services, including your location and account details.',
                          'Your data is never sold to third parties and is handled in accordance with applicable privacy laws.',
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // ── Full-screen routes, outside the shell ─────────────────────────
      GoRoute(
        path: routeVehicle,
        name: 'vehicle',
        pageBuilder: (context, state) =>
            _slidePage(state, const VehicleDetailsScreen()),
      ),

      // ── Delivery flow — full screen, outside the shell ────────────────
      GoRoute(
        path: routeOffer,
        name: 'offer',
        pageBuilder: (context, state) =>
            _sheetPage(state, const OfferScreen(), name: 'offer'),
      ),
      GoRoute(
        path: routeNavigateToMerchant,
        name: 'navigateToMerchant',
        pageBuilder: (context, state) =>
            _slidePage(state, const NavigateToMerchantScreen()),
      ),
      GoRoute(
        path: routeAtMerchant,
        name: 'atMerchant',
        pageBuilder: (context, state) =>
            _slidePage(state, const AtMerchantScreen()),
      ),
      GoRoute(
        path: routeConfirmPickup,
        name: 'confirmPickup',
        pageBuilder: (context, state) =>
            _slidePage(state, const ConfirmPickupScreen()),
      ),
      GoRoute(
        path: routeNavigateToCustomer,
        name: 'navigateToCustomer',
        pageBuilder: (context, state) =>
            _slidePage(state, const NavigateToCustomerScreen()),
      ),
      GoRoute(
        path: routeAtCustomer,
        name: 'atCustomer',
        pageBuilder: (context, state) =>
            _slidePage(state, const AtCustomerScreen()),
      ),
      GoRoute(
        path: routeCompleteDelivery,
        name: 'completeDelivery',
        pageBuilder: (context, state) =>
            _slidePage(state, const CompleteDeliveryScreen()),
      ),

    ],
  );
});
