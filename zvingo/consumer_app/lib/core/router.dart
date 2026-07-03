import 'package:consumer_app/features/address/add_address_screen.dart';
import 'package:consumer_app/features/address/saved_address.dart';
import 'package:consumer_app/features/address/saved_addresses_screen.dart';
import 'package:consumer_app/features/checkout/checkout_screen.dart';
import 'package:consumer_app/features/auth/login_screen.dart';
import 'package:consumer_app/features/auth/register_screen.dart';
import 'package:consumer_app/features/home/home_screen.dart';
import 'package:consumer_app/features/pickup/pickup_screen.dart';
import 'package:consumer_app/features/search/search_screen.dart';
import 'package:consumer_app/features/offers/offers_screen.dart';
import 'package:consumer_app/features/filter/filter_screen.dart';
import 'package:consumer_app/features/favourites/favourites_screen.dart';
import 'package:consumer_app/features/order/orders_screen.dart';
import 'package:consumer_app/features/account/account_screen.dart';
import 'package:consumer_app/features/cart/cart_screen.dart';
import 'package:consumer_app/features/restaurant/menu_screen.dart';
import 'package:consumer_app/features/order/order_tracking_screen.dart';
import 'package:consumer_app/features/payment/payment_screen.dart';
import 'package:consumer_app/features/shell/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

bool _isLoggedIn() {
  final box = Hive.box('settings');
  final token = box.get('access_token');
  return token != null && token.toString().isNotEmpty;
}

@riverpod
GoRouter router(RouterRef ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    redirect: (context, state) {
      final loggedIn = _isLoggedIn();
      final location = state.matchedLocation;
      final isAuthRoute = location == '/login' || location == '/register';

      if (!loggedIn && !isAuthRoute) return '/login';
      if (loggedIn && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      // ── Auth (outside shell) ──────────────────────────
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RegisterScreen(),
      ),

      // ── Main App Shell ────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(
            currentIndex: navigationShell.currentIndex,
            onTabChanged: (index) => navigationShell.goBranch(index),
            child: navigationShell,
          );
        },
        branches: [
          // Tab 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Tab 1: Pickup
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/pickup',
                builder: (context, state) => const PickupScreen(),
              ),
            ],
          ),
          // Tab 2: Offers (replaced Search tab per article)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/offers',
                builder: (context, state) => const OffersScreen(),
              ),
            ],
          ),
          // Tab 3: Orders
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/orders',
                builder: (context, state) => const OrdersScreen(),
              ),
            ],
          ),
          // Tab 4: Account
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                builder: (context, state) => const AccountScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Detail routes (full-screen, outside shell) ────
      GoRoute(
        path: '/search',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/filters',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const FilterScreen(),
      ),
      GoRoute(
        path: '/favourites',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const FavouritesScreen(),
      ),
      GoRoute(
        path: '/restaurant/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            MenuScreen(restaurantId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/cart',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: '/checkout',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final restaurantId = state.uri.queryParameters['restaurantId'];
          return CheckoutScreen(restaurantId: restaurantId);
        },
      ),
      GoRoute(
        path: '/order/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            OrderTrackingScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/addresses',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SavedAddressesScreen(),
      ),
      GoRoute(
        path: '/addresses/add',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AddAddressScreen(),
      ),
      GoRoute(
        path: '/addresses/edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            AddAddressScreen(existing: state.extra as SavedAddress?),
      ),
      GoRoute(
        path: '/payment/:orderId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final amount = double.tryParse(
            state.uri.queryParameters['amount'] ?? '0',
          ) ?? 0.0;
          return PaymentScreen(
            orderId: state.pathParameters['orderId']!,
            amount: amount,
          );
        },
      ),
    ],
  );
}
