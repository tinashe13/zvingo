import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'orders_screen.g.dart';

@riverpod
Future<List<Map<String, dynamic>>> consumerOrders(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  // Get consumer ID from the settings box (stored during login)
  final box = Hive.box('settings');
  final token = box.get('access_token');
  if (token == null) return [];

  try {
    // Get user profile to get ID
    final meResponse = await dio.get('/auth/me');
    final userId = meResponse.data['id'];
    final response = await dio.get('/orders/consumer/$userId');
    return (response.data as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  } catch (e) {
    return [];
  }
}

/// Orders history tab
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  bool _showActive = true;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(consumerOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Text('Orders', style: AppTextStyles.headlineMedium),
            ),
            // Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _showActive = true),
                    child: _tabPill('Active', _showActive),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => setState(() => _showActive = false),
                    child: _tabPill('Past', !_showActive),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ordersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    const Center(child: Text('Error loading orders')),
                data: (orders) {
                  final activeStates = [
                    'CREATED',
                    'OFFERED',
                    'ACCEPTED',
                    'ARRIVED_AT_MERCHANT',
                    'PICKED_UP',
                    'ARRIVED_AT_CUSTOMER'
                  ];
                  final pastStates = ['DELIVERED', 'CANCELLED'];

                  final filtered = orders.where((o) {
                    final state = o['state'] ?? '';
                    return _showActive
                        ? activeStates.contains(state)
                        : pastStates.contains(state);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long,
                              size: 64,
                              color: AppColors.primary.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          Text(
                            _showActive ? 'No active orders' : 'No past orders',
                            style: AppTextStyles.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _showActive
                                ? 'Your active orders will appear here'
                                : 'Your order history will appear here',
                            style: AppTextStyles.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(consumerOrdersProvider);
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final order = filtered[index];
                        return _buildOrderCard(order);
                      },
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

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final state = order['state'] ?? 'CREATED';
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final items = (order['items'] as List?) ?? [];
    final itemNames = items.map((i) => i['name'] ?? '').join(', ');
    final orderId = order['id'] ?? '';

    Color stateColor;
    switch (state) {
      case 'CREATED':
        stateColor = Colors.orange;
        break;
      case 'ACCEPTED':
        stateColor = AppColors.primary;
        break;
      case 'PICKED_UP':
        stateColor = Colors.blue;
        break;
      case 'DELIVERED':
        stateColor = AppColors.primary;
        break;
      case 'CANCELLED':
        stateColor = AppColors.error;
        break;
      default:
        stateColor = AppColors.textSecondary;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if ([
            'CREATED',
            'OFFERED',
            'ACCEPTED',
            'ARRIVED_AT_MERCHANT',
            'PICKED_UP',
            'ARRIVED_AT_CUSTOMER'
          ].contains(state)) {
            context.push('/order/$orderId');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      '#${orderId.substring(orderId.length > 6 ? orderId.length - 6 : 0)}',
                      style: AppTextStyles.titleSmall),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: stateColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(state.replaceAll('_', ' '),
                        style: AppTextStyles.labelSmall.copyWith(
                            color: stateColor, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(itemNames.isNotEmpty ? itemNames : 'Order items',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Text('\$${total.toStringAsFixed(2)}',
                  style: AppTextStyles.titleSmall
                      .copyWith(color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabPill(String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : AppColors.background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelLarge.copyWith(
          color: selected ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}
