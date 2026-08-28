import 'package:consumer_app/common/widgets/app_ui.dart';
import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/order/order_live_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'orders_screen.g.dart';

@riverpod
Future<List<Map<String, dynamic>>> consumerOrders(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final token = Hive.box('settings').get('access_token');
  if (token == null) return [];
  try {
    final meResponse = await dio.get('/auth/me');
    final userId = meResponse.data['id'];
    final response = await dio.get('/orders/consumer/$userId');
    return (response.data as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } catch (_) {
    return [];
  }
}

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  bool _showActive = true;
  String? _selectedOrderId;

  static const _activeStates = {
    'CREATED',
    'OFFERED',
    'ACCEPTED',
    'PREPARING',
    'ARRIVED_AT_MERCHANT',
    'READY_FOR_PICKUP',
    'PICKED_UP',
    'EN_ROUTE',
    'ARRIVED_AT_CUSTOMER',
  };

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(consumerOrdersProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppPageTitle(
              eyebrow: 'Your activity',
              title: 'Orders',
              subtitle:
                  'Track what is arriving and quickly reorder favourites.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _tab('Active', _showActive,
                        () => setState(() => _showActive = true)),
                    _tab('Past', !_showActive,
                        () => setState(() => _showActive = false)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ordersAsync.when(
                loading: () => const _OrdersSkeleton(),
                error: (_, __) => AppEmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Orders unavailable',
                  message: 'Check your connection and try loading them again.',
                  action: ElevatedButton(
                    onPressed: () => ref.invalidate(consumerOrdersProvider),
                    child: const Text('Try again'),
                  ),
                ),
                data: (orders) {
                  final filtered = orders.where((order) {
                    final state = _state(order);
                    return _showActive
                        ? _activeStates.contains(state)
                        : {'DELIVERED', 'CANCELLED'}.contains(state);
                  }).toList();
                  if (filtered.isEmpty) {
                    return AppEmptyState(
                      icon: _showActive
                          ? Icons.delivery_dining_rounded
                          : Icons.receipt_long_rounded,
                      title: _showActive
                          ? 'Nothing on the way'
                          : 'No past orders yet',
                      message: _showActive
                          ? 'When you place an order, live tracking will appear here.'
                          : 'Your completed orders will be ready to reorder from here.',
                      action: _showActive
                          ? ElevatedButton(
                              onPressed: () => context.go('/home'),
                              child: const Text('Find food'),
                            )
                          : null,
                    );
                  }
                  if (!_showActive) {
                    return RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(consumerOrdersProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 118),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => _OrderCard(
                          order: filtered[index],
                          active: false,
                          onTap: () {},
                        ),
                      ),
                    );
                  }

                  final selectedId = filtered.any(
                    (order) => order['id']?.toString() == _selectedOrderId,
                  )
                      ? _selectedOrderId!
                      : filtered.first['id'].toString();
                  final selectedOrder = filtered.firstWhere(
                    (order) => order['id']?.toString() == selectedId,
                  );

                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(consumerOrdersProvider),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 118),
                      children: [
                        OrderLiveMap(
                          key: ValueKey(selectedId),
                          orderId: selectedId,
                          initialState: _state(selectedOrder),
                          onOpenTracking: () =>
                              context.push('/order/$selectedId'),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                filtered.length == 1
                                    ? 'Current order'
                                    : 'Your active orders',
                                style: AppTextStyles.titleMedium,
                              ),
                            ),
                            if (filtered.length > 1)
                              Text(
                                'Tap to switch map',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        ...filtered.map((order) {
                          final id = order['id']?.toString() ?? '';
                          final selected = id == selectedId;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _OrderCard(
                              order: order,
                              active: true,
                              selected: selected,
                              onTap: () {
                                if (id.isEmpty) return;
                                if (!selected) {
                                  setState(() => _selectedOrderId = id);
                                } else {
                                  context.push('/order/$id');
                                }
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.selectedDark : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(label,
              style: AppTextStyles.labelLarge.copyWith(
                  color: selected ? AppColors.white : AppColors.textSecondary)),
        ),
      ),
    );
  }
}

String _state(Map<String, dynamic> order) =>
    (order['state'] ?? 'CREATED').toString().replaceFirst('OrderState.', '');

class _OrderCard extends StatelessWidget {
  const _OrderCard(
      {required this.order,
      required this.active,
      required this.onTap,
      this.selected = false});
  final Map<String, dynamic> order;
  final bool active;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final state = _state(order);
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final items = (order['items'] as List?) ?? const [];
    final id = order['id']?.toString() ?? '';
    final shortId =
        id.substring(id.length > 6 ? id.length - 6 : 0).toUpperCase();
    final status = _statusFor(state);
    return AppSurface(
      onTap: onTap,
      color: selected ? AppColors.primarySurface : AppColors.surface,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: status.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(status.icon, color: status.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        status.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: status.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  items.isEmpty
                      ? 'Order #$shortId'
                      : items
                          .map((item) =>
                              '${item['quantity'] ?? 1}× ${item['name'] ?? ''}')
                          .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  active ? status.detail : 'Order #$shortId',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: active ? status.color : AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: AppTextStyles.labelLarge,
              ),
              const SizedBox(height: 10),
              Icon(
                selected ? Icons.map_rounded : Icons.chevron_right_rounded,
                color:
                    selected ? AppColors.textPrimary : AppColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

({String title, String detail, IconData icon, Color color, Color surface})
    _statusFor(String state) {
  switch (state) {
    case 'CREATED':
    case 'OFFERED':
      return (
        title: 'Order received',
        detail: 'Waiting for the restaurant',
        icon: Icons.receipt_long_rounded,
        color: AppColors.warning,
        surface: AppColors.warningSurface
      );
    case 'ACCEPTED':
    case 'ARRIVED_AT_MERCHANT':
    case 'READY_FOR_PICKUP':
      return (
        title: 'Being prepared',
        detail: 'Your order is in the kitchen',
        icon: Icons.restaurant_rounded,
        color: AppColors.brandGreen,
        surface: AppColors.brandGreenSurface
      );
    case 'PICKED_UP':
      return (
        title: 'On the way',
        detail: 'Your courier has the order',
        icon: Icons.delivery_dining_rounded,
        color: AppColors.info,
        surface: const Color(0xFFEAF2FF)
      );
    case 'ARRIVED_AT_CUSTOMER':
      return (
        title: 'Courier has arrived',
        detail: 'Meet your courier outside',
        icon: Icons.location_on_rounded,
        color: AppColors.info,
        surface: const Color(0xFFEAF2FF)
      );
    case 'DELIVERED':
      return (
        title: 'Delivered',
        detail: 'Thanks for ordering with Zvingo',
        icon: Icons.check_circle_rounded,
        color: AppColors.success,
        surface: AppColors.brandGreenSurface
      );
    default:
      return (
        title: 'Cancelled',
        detail: 'This order was cancelled',
        icon: Icons.cancel_rounded,
        color: AppColors.error,
        surface: AppColors.errorSurface
      );
  }
}

class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();
  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 118),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          height: 172,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
}
