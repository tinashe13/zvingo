import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/common/widgets/zv_screen.dart';
import 'package:consumer_app/common/widgets/zv_states.dart';
import 'package:consumer_app/core/app_motion.dart';
import 'package:consumer_app/features/account/account_screen.dart';
import 'package:consumer_app/features/account/help_screen.dart';
import 'package:consumer_app/features/account/manage_account_screen.dart';
import 'package:consumer_app/features/account/payment_methods_screen.dart';
import 'package:consumer_app/features/address/add_address_screen.dart';
import 'package:consumer_app/features/address/saved_address.dart';
import 'package:consumer_app/features/address/saved_addresses_screen.dart';
import 'package:consumer_app/features/auth/login_screen.dart';
import 'package:consumer_app/features/auth/register_screen.dart';
import 'package:consumer_app/features/cart/cart_screen.dart';
import 'package:consumer_app/features/checkout/checkout_screen.dart';
import 'package:consumer_app/features/favourites/favourites_screen.dart';
import 'package:consumer_app/features/filter/filter_screen.dart';
import 'package:consumer_app/features/home/home_screen.dart';
import 'package:consumer_app/features/offers/offers_screen.dart';
import 'package:consumer_app/features/order/order_tracking_screen.dart';
import 'package:consumer_app/features/order/orders_screen.dart';
import 'package:consumer_app/features/payment/payment_screen.dart';
import 'package:consumer_app/features/restaurant/menu_screen.dart';
import 'package:consumer_app/features/restaurant/restaurant_map_screen.dart';
import 'package:consumer_app/features/search/search_screen.dart';
import 'package:consumer_app/features/shell/main_shell.dart';

part 'router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

bool _isLoggedIn() {
  final box = Hive.box('settings');
  final token = box.get('access_token');
  return token != null && token.toString().isNotEmpty;
}

/// Human-readable titles for every non-top-level route, keyed by path.
///
/// A route with no title is a route the user can get lost on (§5.4). Screens
/// should render the same string as their `ZvScreen(title: ...)`; the router
/// also hands it to [ZvBackGuard] as the accessible name of the fallback back
/// affordance.
const Map<String, String> kRouteTitles = <String, String>{
  '/offers': 'Offers',
  '/filters': 'Filters',
  '/favourites': 'Favourites',
  '/restaurant/:id': 'Restaurant',
  '/cart': 'Your cart',
  '/checkout': 'Checkout',
  '/order/:id': 'Track order',
  '/addresses': 'Saved addresses',
  '/addresses/add': 'Add address',
  '/addresses/edit': 'Edit address',
  '/account/edit': 'Account details',
  '/payment-methods': 'Payment methods',
  '/help': 'Help & support',
  '/payment/:orderId': 'Payment',
};

/// Builds a detail page with the §4.3 forward transition (slide in from the
/// right 24px + fade over `motion/slow` with `ease/enter`) and the §5.4
/// back-affordance guarantee.
///
/// Every route pushed on top of another goes through this, so no screen can
/// ship without a way back.
CustomTransitionPage<void> _detailPage(
  GoRouterState state, {
  required String title,
  required Widget child,
  String fallbackRoute = '/home',
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: title,
    restorationId: state.pageKey.value,
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.slow,
    child: ZvBackGuard(
      title: title,
      fallbackRoute: fallbackRoute,
      child: child,
    ),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return ZvPageTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    },
  );
}

/// Top-level and auth pages cross-fade instead of sliding — there is no
/// "forward" relationship between them.
CustomTransitionPage<void> _fadePage(
  GoRouterState state, {
  required String title,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: title,
    restorationId: state.pageKey.value,
    transitionDuration: AppMotion.base,
    reverseTransitionDuration: AppMotion.fast,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AppMotion.enter),
        child: child,
      );
    },
  );
}

/// Tab branches keep their own navigation stacks and must not animate when
/// the user switches tabs — the dock indicator already communicates the move.
NoTransitionPage<void> _tabPage(
  GoRouterState state, {
  required String title,
  required Widget child,
}) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    name: title,
    restorationId: state.pageKey.value,
    child: child,
  );
}

@riverpod
GoRouter router(Ref ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    restorationScopeId: 'zvingo_router',
    redirect: (context, state) {
      final loggedIn = _isLoggedIn();
      final location = state.matchedLocation;
      final isAuthRoute = location == '/login' || location == '/register';

      if (!loggedIn && !isAuthRoute) return '/login';
      if (loggedIn && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      // ── Auth (outside the shell) ──────────────────────────────────────
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(state, title: 'Sign in', child: const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: 'Create account',
          fallbackRoute: '/login',
          child: const RegisterScreen(),
        ),
      ),

      // ── Main app shell: five tabs, each with its own navigation stack ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(
            currentIndex: navigationShell.currentIndex,
            onTabChanged: (index) => navigationShell.goBranch(
              index,
              // Tapping the active tab returns it to its root, the way every
              // mobile user already expects.
              initialLocation: index == navigationShell.currentIndex,
            ),
            child: navigationShell,
          );
        },
        branches: [
          // Tab 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) =>
                    _tabPage(state, title: 'Home', child: const HomeScreen()),
              ),
            ],
          ),
          // Tab 1: Nearby restaurant map
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  title: 'Nearby',
                  child: const RestaurantMapScreen(),
                ),
              ),
            ],
          ),
          // Tab 2: Search
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  title: 'Search',
                  child: const SearchScreen(embedded: true),
                ),
              ),
            ],
          ),
          // Tab 3: Orders
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/orders',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  title: 'Orders',
                  child: const OrdersScreen(),
                ),
              ),
            ],
          ),
          // Tab 4: Account
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  title: 'Account',
                  child: const AccountScreen(),
                ),
              ),
            ],
          ),
        ],
      ),

      // ── Detail routes (full-screen, above the shell) ───────────────────
      GoRoute(
        path: '/pickup',
        redirect: (context, state) => '/map',
      ),
      GoRoute(
        path: '/offers',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/offers']!,
          child: const OffersScreen(),
        ),
      ),
      GoRoute(
        path: '/filters',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/filters']!,
          child: const FilterScreen(),
        ),
      ),
      GoRoute(
        path: '/favourites',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/favourites']!,
          child: const FavouritesScreen(),
        ),
      ),
      GoRoute(
        path: '/restaurant/:id',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/restaurant/:id']!,
          child: MenuScreen(restaurantId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/cart',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/cart']!,
          child: const CartScreen(),
        ),
      ),
      GoRoute(
        path: '/checkout',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/checkout']!,
          fallbackRoute: '/cart',
          child: CheckoutScreen(
            restaurantId: state.uri.queryParameters['restaurantId'],
          ),
        ),
      ),
      GoRoute(
        path: '/order/:id',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/order/:id']!,
          fallbackRoute: '/orders',
          child: OrderTrackingScreen(orderId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/addresses',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/addresses']!,
          fallbackRoute: '/account',
          child: const SavedAddressesScreen(),
        ),
      ),
      GoRoute(
        path: '/addresses/add',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/addresses/add']!,
          fallbackRoute: '/addresses',
          child: const AddAddressScreen(),
        ),
      ),
      GoRoute(
        path: '/addresses/edit',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/addresses/edit']!,
          fallbackRoute: '/addresses',
          child: AddAddressScreen(existing: state.extra as SavedAddress?),
        ),
      ),
      GoRoute(
        path: '/account/edit',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/account/edit']!,
          fallbackRoute: '/account',
          child: const ManageAccountScreen(),
        ),
      ),
      GoRoute(
        path: '/payment-methods',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/payment-methods']!,
          fallbackRoute: '/account',
          child: const PaymentMethodsScreen(),
        ),
      ),
      GoRoute(
        path: '/help',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _detailPage(
          state,
          title: kRouteTitles['/help']!,
          fallbackRoute: '/account',
          child: const HelpScreen(),
        ),
      ),
      GoRoute(
        path: '/payment/:orderId',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final amount =
              double.tryParse(state.uri.queryParameters['amount'] ?? '0') ?? 0;
          return _detailPage(
            state,
            title: kRouteTitles['/payment/:orderId']!,
            fallbackRoute: '/orders',
            child: PaymentScreen(
              orderId: state.pathParameters['orderId']!,
              amount: amount,
            ),
          );
        },
      ),
    ],

    // Never a dead end: an unknown deep link explains itself and offers a way
    // back into the app instead of showing a raw go_router error page.
    errorBuilder: (context, state) => ZvScreen(
      title: 'Page not found',
      showBack: true,
      child: ZvEmptyState(
        icon: Icons.explore_off_rounded,
        title: "We couldn't find that page",
        message: 'The link may be out of date. Head back to the home screen '
            'and try again.',
        actionLabel: 'Go to home',
        onAction: () => GoRouter.of(context).go('/home'),
      ),
    ),
  );
}
