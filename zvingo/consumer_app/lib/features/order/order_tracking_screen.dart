import 'dart:async';
import 'dart:convert';
import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/core/app_config.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart' hide Marker;

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  String status = 'Preparing';
  String _orderState = 'CREATED'; // Raw order state from backend
  int _currentStep = 1; // 0: Confirmed, 1: Preparing, 2: En Route, 3: Delivered
  bool _confirmingDelivery = false;
  bool _cancellingOrder = false;
  Timer? _statusPollTimer; // Timer for polling order status
  
  // Map State
  final MapController _mapController = MapController();
  LatLng _driverLocation = const LatLng(-17.8216, 31.0492); // Default to Harare
  LatLng? _deliveryLocation;
  LatLng? _pickupLocation;
  bool _hasDriverLocation = false;
  
  String driverId = '';
  String driverName = '';
  bool _loading = true;
  String _lottieAsset = 'assets/animations/cooking.json';

  /// Check if consumer can confirm delivery (driver picked up or arrived)
  bool get _canConfirmDelivery => 
      _orderState == 'PICKED_UP' || _orderState == 'ARRIVED_AT_CUSTOMER';

  /// Check if consumer can cancel order (before pickup)
  bool get _canCancel => !['PICKED_UP', 'ARRIVED_AT_CUSTOMER', 'DELIVERED', 'CANCELLED'].contains(_orderState);

  /// Cancel order via backend API
  Future<void> _cancelOrder() async {
    if (_cancellingOrder) return;
    
    // Confirm cancellation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text('Are you sure you want to cancel this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _cancellingOrder = true);
    
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post('/orders/${widget.orderId}/cancel');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order cancelled successfully'),
            backgroundColor: Colors.orange,
          ),
        );
        context.pop(); // Go back after cancellation
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cancellingOrder = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Confirm delivery via backend API
  Future<void> _confirmDelivery() async {
    if (_confirmingDelivery) return;
    
    setState(() => _confirmingDelivery = true);
    
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post('/orders/${widget.orderId}/confirm-delivery');
      
      if (mounted) {
        setState(() {
          _orderState = 'DELIVERED';
          _currentStep = 3;
          status = 'Delivered';
          _lottieAsset = 'assets/animations/delivered.json';
          _confirmingDelivery = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery confirmed! Enjoy your meal!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _confirmingDelivery = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm delivery: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _fitMapToTrip() {
    final points = <LatLng>[];
    
    // Only add valid coordinates (not 0,0 which is null island)
    if (_pickupLocation != null && 
        (_pickupLocation!.latitude.abs() > 0.01 || _pickupLocation!.longitude.abs() > 0.01)) {
      points.add(_pickupLocation!);
    }
    if (_deliveryLocation != null && 
        (_deliveryLocation!.latitude.abs() > 0.01 || _deliveryLocation!.longitude.abs() > 0.01)) {
      points.add(_deliveryLocation!);
    }
    if (_hasDriverLocation && 
        (_driverLocation.latitude.abs() > 0.01 || _driverLocation.longitude.abs() > 0.01)) {
      points.add(_driverLocation);
    }
    if (points.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        if (points.length == 1) {
          _mapController.move(points.first, 15.5);
          return;
        }

        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(56),
          ),
        );
      } catch (e) {
        // Fallback: just center on first point if bounds calculation fails
        debugPrint('Map fit error: $e');
        _mapController.move(points.first, 14.0);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchOrderDetails();
    // Start polling for order status updates every 3 seconds
    _statusPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollOrderStatus();
    });
  }

  /// Fetch order details from backend to get driver info and current state
  Future<void> _fetchOrderDetails() async {
    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.get('/orders/${widget.orderId}');
      final data = response.data;

      if (mounted) {
        setState(() {
          _loading = false;
          driverId = data['driver_id'] ?? '';
          driverName = (data['driver_name'] as String?)?.split(' ').first ?? '';
          
          // Try to get delivery location if available
          if (data['delivery_lat'] != null && data['delivery_lng'] != null) {
             _deliveryLocation = LatLng(
                 (data['delivery_lat'] as num).toDouble(), 
                 (data['delivery_lng'] as num).toDouble()
             );
          }

          // Try to get pickup location (Store)
          if (data['pickup_lat'] != null && data['pickup_lng'] != null) {
             _pickupLocation = LatLng(
                 (data['pickup_lat'] as num).toDouble(), 
                 (data['pickup_lng'] as num).toDouble()
             );
          }

          // Get driver's current location from polling (fallback for SSE)
          if (data['driver_lat'] != null && data['driver_lng'] != null) {
            _driverLocation = LatLng(
              (data['driver_lat'] as num).toDouble(),
              (data['driver_lng'] as num).toDouble(),
            );
            _hasDriverLocation = true;
          }

          // Map order state to step index
          // Strip 'OrderState.' prefix if present (backend enum format)
          String state = data['state'] ?? 'CREATED';
          if (state.startsWith('OrderState.')) {
            state = state.replaceFirst('OrderState.', '');
          }
          _orderState = state; // Store raw state for confirm/cancel button logic
          switch (state) {
            case 'CREATED':
              _currentStep = 0;
              status = 'Confirmed';
              _lottieAsset = 'assets/animations/order_confirmed.json';
              break;
            case 'ACCEPTED':
            case 'PREPARING':
            case 'ARRIVED_AT_MERCHANT':
            case 'READY_FOR_PICKUP':
              _currentStep = 1;
              status = 'Preparing';
              _lottieAsset = 'assets/animations/cooking.json';
              break;
            case 'PICKED_UP':
            case 'EN_ROUTE':
              _currentStep = 2;
              status = 'En Route';
              _lottieAsset = 'assets/animations/delivery.json';
              break;
            case 'ARRIVED_AT_CUSTOMER':
              _currentStep = 2;
              status = 'Driver Arrived';
              _lottieAsset = 'assets/animations/delivery.json';
              break;
            case 'DELIVERED':
              _currentStep = 3;
              status = 'Delivered';
              _lottieAsset = 'assets/animations/delivered.json';
              break;
            default:
              _currentStep = 0;
              status = state;
              _lottieAsset = 'assets/animations/cooking.json';
          }
        });

        // Start SSE subscription if driver is assigned
        if (driverId.isNotEmpty) {
          _subscribeToDriver();
        }

        _fitMapToTrip();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
          setState(() {
            _orderState = state;
            driverId = data['driver_id'] ?? driverId;
            driverName = (data['driver_name'] as String?)?.split(' ').first ?? driverName;
            
            // Update driver location from polling (fallback for SSE)
            if (data['driver_lat'] != null && data['driver_lng'] != null) {
              _driverLocation = LatLng(
                (data['driver_lat'] as num).toDouble(),
                (data['driver_lng'] as num).toDouble(),
              );
              _hasDriverLocation = true;
            }
            
            switch (state) {
              case 'CREATED':
                _currentStep = 0;
                status = 'Confirmed';
                _lottieAsset = 'assets/animations/order_confirmed.json';
                break;
              case 'ACCEPTED':
              case 'PREPARING':
              case 'ARRIVED_AT_MERCHANT':
              case 'READY_FOR_PICKUP':
                _currentStep = 1;
                status = 'Preparing';
                _lottieAsset = 'assets/animations/cooking.json';
                break;
              case 'PICKED_UP':
              case 'EN_ROUTE':
                _currentStep = 2;
                status = 'En Route';
                _lottieAsset = 'assets/animations/delivery.json';
                break;
              case 'ARRIVED_AT_CUSTOMER':
                _currentStep = 2;
                status = 'Driver Arrived';
                _lottieAsset = 'assets/animations/delivery.json';
                break;
              case 'DELIVERED':
                _currentStep = 3;
                status = 'Delivered';
                _lottieAsset = 'assets/animations/delivered.json';
                _statusPollTimer?.cancel(); // Stop polling after delivery
                break;
              case 'CANCELLED':
                _currentStep = 0;
                status = 'Cancelled';
                _statusPollTimer?.cancel(); // Stop polling after cancel
                break;
              default:
                status = state;
            }
          });
          
          // Start driver tracking if driver just got assigned
          if (driverId.isNotEmpty && !_hasDriverLocation) {
            _subscribeToDriver();
          }
        } else {
          // State didn't change but driver location might have
          if (data['driver_lat'] != null && data['driver_lng'] != null) {
            setState(() {
              _driverLocation = LatLng(
                (data['driver_lat'] as num).toDouble(),
                (data['driver_lng'] as num).toDouble(),
              );
              _hasDriverLocation = true;
            });
          }
        }
      }
    } catch (e) {
      // Silently ignore polling errors
    }
  }

  void _subscribeToDriver() {
    if (driverId.isEmpty) return;
    
    // We'll use the tracked driver ID
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
            final isFirst = !_hasDriverLocation;
            setState(() {
              _driverLocation = LatLng(lat, lng);
              _hasDriverLocation = true;
            });
            // Only fit bounds on first location; after that, smoothly follow
            if (isFirst) {
              _fitMapToTrip();
            }
          }
        } catch (e) {
          // Ignore malformed events
        }
      }
    });

  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    SSEClient.unsubscribeFromSSE();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Column(
        children: [
          // ── Map Section (top half) ─────────────────
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.40,
            child: Stack(
              children: [
                // Real Map
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _hasDriverLocation ? _driverLocation : (_deliveryLocation ?? _driverLocation),
                    initialZoom: 14.5,
                  ),
                  children: [
                    TileLayer(
                      // Use CartoDB Voyager for a cleaner, Google-like look
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.zvingo.consumer',
                    ),
                    PolylineLayer(
                      polylines: [
                        if (_pickupLocation != null && _deliveryLocation != null)
                          Polyline(
                            points: [_pickupLocation!, _deliveryLocation!],
                            strokeWidth: 5,
                            color: AppColors.primary.withOpacity(0.85),
                          ),
                        if (_hasDriverLocation && _deliveryLocation != null)
                          Polyline(
                            points: [_driverLocation, _deliveryLocation!],
                            strokeWidth: 4,
                            color: AppColors.info.withOpacity(0.8),
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        // Driver Marker
                        if (_hasDriverLocation)
                          Marker(
                            point: _driverLocation,
                            width: 48,
                            height: 48,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.primary, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ]
                              ),
                              padding: const EdgeInsets.all(6),
                              child: const Icon(
                                Icons.delivery_dining,
                                color: AppColors.primary,
                                size: 26,
                              ),
                            ),
                          ),
                          
                        // Delivery Location Marker (Customer)
                        if (_deliveryLocation != null)
                           Marker(
                            point: _deliveryLocation!,
                            width: 30,
                            height: 30,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 30,
                            ),
                          ),

                        // Pickup Location Marker (Store)
                        if (_pickupLocation != null)
                           Marker(
                            point: _pickupLocation!,
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                  )
                                ]
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.store,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Back button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back, size: 22),
                    ),
                  ),
                ),

                // Title
                Positioned(
                  top: MediaQuery.of(context).padding.top + 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12)
                      ),
                      child: Text('Order Status', style: AppTextStyles.titleLarge),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom Detail Panel ───────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      children: [
                        // ── Driver Info Card ──────────────────
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.primarySurface,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: driverName.isNotEmpty
                                      ? Text(
                                          driverName.substring(0, 1).toUpperCase(),
                                          style: AppTextStyles.titleMedium.copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        )
                                      : const Icon(Icons.person,
                                          color: AppColors.primary, size: 24),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      driverName.isNotEmpty ? driverName : 'Assigning driver...',
                                      style: AppTextStyles.titleSmall,
                                    ),
                                    Text('Delivery Driver',
                                        style: AppTextStyles.bodySmall),
                                  ],
                                ),
                              ),
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.divider),
                                ),
                                child: const Icon(Icons.chat_bubble_outline,
                                    size: 18, color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── ETA ───────────────────────────────
                        Row(
                          children: [
                            Text('Time Line', style: AppTextStyles.titleMedium),
                            const Spacer(),
                            Icon(Icons.access_time,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              status,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── Timeline Steps ────────────────────
                        _timelineStep(
                          icon: Icons.check_circle,
                          title: 'Order Confirmed',
                          subtitle: 'Your order has been placed',
                          isCompleted: _currentStep >= 0,
                          isLast: false,
                        ),
                        _timelineStep(
                          icon: Icons.restaurant,
                          title: 'Kitchen',
                          subtitle: 'Preparing your food',
                          isCompleted: _currentStep >= 1,
                          isLast: false,
                        ),
                        _timelineStep(
                          icon: Icons.delivery_dining,
                          title: 'Delivery',
                          subtitle: 'On the way to you',
                          isCompleted: _currentStep >= 2,
                          isLast: true,
                        ),
                        if (_currentStep == 3) // Show delivered step explicitly if delivered
                           _timelineStep(
                            icon: Icons.home,
                            title: 'Delivered',
                            subtitle: 'Enjoy your food!',
                            isCompleted: true,
                            isLast: true,
                          ),

                        // ── Confirm Delivery Button ────────────────────
                        if (_canConfirmDelivery) ...[
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: _confirmingDelivery ? null : _confirmDelivery,
                              icon: _confirmingDelivery 
                                  ? const SizedBox(
                                      width: 20, 
                                      height: 20, 
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2, 
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                              label: Text(
                                _confirmingDelivery 
                                    ? 'Confirming...' 
                                    : 'Confirm Delivery',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to confirm you received your order',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        // ── Cancel Order Button ────────────────────
                        if (_canCancel) ...[
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _cancellingOrder ? null : _cancelOrder,
                              icon: _cancellingOrder 
                                  ? const SizedBox(
                                      width: 18, 
                                      height: 18, 
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2, 
                                        color: Colors.red,
                                      ),
                                    )
                                  : const Icon(Icons.cancel_outlined, size: 20),
                              label: Text(
                                _cancellingOrder 
                                    ? 'Cancelling...' 
                                    : 'Cancel Order',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineStep({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Circle + Line
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted ? AppColors.primary : AppColors.background,
                border: Border.all(
                  color: isCompleted ? AppColors.primary : AppColors.divider,
                  width: 2,
                ),
              ),
              child: isCompleted
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Icon(icon, size: 14, color: AppColors.textHint),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isCompleted ? AppColors.primary : AppColors.divider,
              ),
          ],
        ),
        const SizedBox(width: 14),

        // Text
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16,
                        color: isCompleted
                            ? AppColors.primary
                            : AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: isCompleted
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(subtitle, style: AppTextStyles.bodySmall),
                ),
                if (!isLast) const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
