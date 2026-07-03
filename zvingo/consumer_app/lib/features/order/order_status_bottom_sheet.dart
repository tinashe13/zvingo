import 'dart:async';
import 'dart:convert';
import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/core/app_config.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/order/active_order_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

class OrderStatusBottomSheet extends ConsumerStatefulWidget {
  final String orderId;
  const OrderStatusBottomSheet({super.key, required this.orderId});

  @override
  ConsumerState<OrderStatusBottomSheet> createState() =>
      _OrderStatusBottomSheetState();
}

class _OrderStatusBottomSheetState
    extends ConsumerState<OrderStatusBottomSheet>
    with SingleTickerProviderStateMixin {
  String _status = 'Preparing';
  String _orderState = 'CREATED';
  String _lottieAsset = 'assets/animations/cooking.json';
  double? _driverLat;
  double? _driverLng;
  String? _driverId;
  String? _driverName;
  bool _loading = true;
  Timer? _statusPollTimer;

  // For the progress bar animation
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _fetchOrderDetails();
    // Start polling for order status updates every 3 seconds
    _statusPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollOrderStatus();
    });
  }

  @override
  void didUpdateWidget(covariant OrderStatusBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _fetchOrderDetails();
    }
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _progressController.dispose();
    SSEClient.unsubscribeFromSSE();
    super.dispose();
  }

  Future<void> _fetchOrderDetails() async {
    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.get('/orders/${widget.orderId}');
      final data = response.data;

      if (mounted) {
        _updateState(data);
        // Subscribe to driver location updates if driver is assigned
        if (data['driver_id'] != null && _driverId == null) {
          _driverId = data['driver_id'];
          _subscribeToDriver(data['driver_id']);
        }
      }
    } catch (e) {
      debugPrint('Error fetching order: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updateState(Map<String, dynamic> data) {
    String state = data['state'] ?? 'CREATED';
    // Strip 'OrderState.' prefix if present (backend enum format)
    if (state.startsWith('OrderState.')) {
      state = state.replaceFirst('OrderState.', '');
    }
    setState(() {
      _orderState = state;
      final rawName = data['driver_name'] as String?;
      _driverName = rawName?.split(' ').first;
      
      switch (state) {
        case 'CREATED':
          _status = 'Order Confirmed';
          _lottieAsset = 'assets/animations/order_confirmed.json';
          break;
        case 'ACCEPTED':
        case 'PREPARING':
        case 'ARRIVED_AT_MERCHANT':
        case 'READY_FOR_PICKUP':
          _status = 'Preparing your food';
          _lottieAsset = 'assets/animations/cooking.json';
          break;
        case 'PICKED_UP':
        case 'EN_ROUTE':
          _status = 'On the way';
          _lottieAsset = 'assets/animations/delivery.json';
          break;
        case 'ARRIVED_AT_CUSTOMER':
          _status = 'Driver Arrived';
          _lottieAsset = 'assets/animations/delivery.json';
          break;
        case 'DELIVERED':
          _status = 'Delivered';
          _lottieAsset = 'assets/animations/delivered.json';
          _statusPollTimer?.cancel();
          // Auto-dismiss after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              ref.read(activeOrderProvider.notifier).state = null;
            }
          });
          break;
        case 'CANCELLED':
          _status = 'Cancelled';
          _lottieAsset = 'assets/animations/cooking.json';
          _statusPollTimer?.cancel();
          // Auto-dismiss after 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              ref.read(activeOrderProvider.notifier).state = null;
            }
          });
          break;
        default:
          _status = 'Processing';
          _lottieAsset = 'assets/animations/cooking.json';
      }
    });
  }

  /// Poll order status to get real-time updates from driver actions
  Future<void> _pollOrderStatus() async {
    if (!mounted) return;
    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.get('/orders/${widget.orderId}');
      final data = response.data;

      if (mounted) {
        String state = data['state'] ?? 'CREATED';
        if (state.startsWith('OrderState.')) {
          state = state.replaceFirst('OrderState.', '');
        }
        
        // Only update if state changed
        if (state != _orderState) {
          _updateState(data);
        }
        
        // Start driver tracking if driver just got assigned
        if (data['driver_id'] != null && _driverId == null) {
          _driverId = data['driver_id'];
          final rawName = data['driver_name'] as String?;
          _driverName = rawName?.split(' ').first;
          _subscribeToDriver(data['driver_id']);
          setState(() {});
        }
      }
    } catch (e) {
      // Silently ignore polling errors
    }
  }

  void _subscribeToDriver(String driverId) {
    if (driverId.isEmpty) return;
    
    final url = '${AppConfig.apiBaseUrl}/location/driver/$driverId/track';
    
    SSEClient.subscribeToSSE(
      method: SSERequestType.GET,
      url: url,
      header: {
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    ).listen((event) {
      if (event.data != null && event.data!.isNotEmpty) {
        try {
          final parsed = jsonDecode(event.data!);
          final lat = (parsed['lat'] as num?)?.toDouble();
          final lng = (parsed['lng'] as num?)?.toDouble();
          
          if (lat != null && lng != null && mounted) {
            setState(() {
              _driverLat = lat;
              _driverLng = lng;
            });
          }
        } catch (e) {
          // Ignore malformed events
        }
      }
    });
  }

  /// Get appropriate subtitle text based on order state and driver info
  String _getSubtitleText() {
    switch (_orderState) {
      case 'CREATED':
        return 'Waiting for restaurant to confirm';
      case 'ACCEPTED':
      case 'PREPARING':
      case 'ARRIVED_AT_MERCHANT':
      case 'READY_FOR_PICKUP':
        if (_driverName != null) {
          return '$_driverName is picking up your order';
        }
        return 'Restaurant is preparing your order';
      case 'PICKED_UP':
      case 'EN_ROUTE':
        if (_driverName != null && _driverLat != null && _driverLng != null) {
          return '$_driverName is on the way';
        } else if (_driverName != null) {
          return '$_driverName is heading to you';
        }
        return 'Driver is on the way';
      case 'ARRIVED_AT_CUSTOMER':
        return _driverName != null ? '$_driverName has arrived!' : 'Driver has arrived!';
      case 'DELIVERED':
        return 'Enjoy your meal!';
      case 'CANCELLED':
        return 'Order was cancelled';
      default:
        return 'Estimated arrival: 25 min';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(widget.orderId),
      direction: DismissDirection.down,
      onDismissed: (_) {
        ref.read(activeOrderProvider.notifier).state = null;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/order/${widget.orderId}'),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                // Animation Icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Lottie.asset(
                      _lottieAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, _, __) => const Icon(Icons.fastfood, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                
                // Text Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _status, 
                        style: AppTextStyles.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getSubtitleText(),
                        style: AppTextStyles.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      // Animated Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, child) {
                            return LinearProgressIndicator(
                              value: 0.6, // Placeholder progress
                              backgroundColor: AppColors.background,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color.lerp(
                                  AppColors.primary, 
                                  AppColors.primaryDark, 
                                  _progressController.value
                                )!,
                              ),
                              minHeight: 4,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // View Button
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
