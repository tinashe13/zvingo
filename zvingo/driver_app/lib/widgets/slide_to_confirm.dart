import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_colors.dart';

/// SlideToConfirm — drag-to-confirm gesture widget.
/// Port of SlideToConfirm.kt — shimmer animation, haptic feedback, spring snap-back.
class SlideToConfirm extends StatefulWidget {
  final String text;
  final VoidCallback onConfirm;
  final bool enabled;
  final bool isLoading;

  const SlideToConfirm({
    super.key,
    required this.text,
    required this.onConfirm,
    this.enabled = true,
    this.isLoading = false,
  });

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _isConfirmed = false;
  bool _hasHapticTriggered = false;

  late AnimationController _shimmerController;

  static const double _trackHeight = 64;
  static const double _thumbSize = 56;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxDrag = constraints.maxWidth - _thumbSize - 8;

      return Container(
        width: double.infinity,
        height: _trackHeight,
        decoration: BoxDecoration(
          color: _isConfirmed
              ? AppColors.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Track label
            if (!_isConfirmed)
              Center(
                child: AnimatedBuilder(
                  animation: _shimmerController,
                  builder: (context, child) {
                    return Text(
                      widget.text,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withOpacity(
                                    0.3 + 0.4 * _shimmerController.value),
                          ),
                    );
                  },
                ),
              ),

            // Thumb
            GestureDetector(
              onHorizontalDragStart: widget.enabled && !_isConfirmed && !widget.isLoading
                  ? (_) {
                      _hasHapticTriggered = false;
                    }
                  : null,
              onHorizontalDragUpdate: widget.enabled && !_isConfirmed && !widget.isLoading
                  ? (details) {
                      setState(() {
                        _dragOffset =
                            (_dragOffset + details.delta.dx).clamp(0, maxDrag);
                      });
                      // Haptic at 80%
                      if (!_hasHapticTriggered && _dragOffset > maxDrag * 0.8) {
                        _hasHapticTriggered = true;
                        HapticFeedback.heavyImpact();
                      }
                    }
                  : null,
              onHorizontalDragEnd: widget.enabled && !_isConfirmed && !widget.isLoading
                  ? (_) {
                      if (_dragOffset > maxDrag * 0.85) {
                        setState(() {
                          _isConfirmed = true;
                          _dragOffset = maxDrag;
                        });
                        widget.onConfirm();
                      } else {
                        setState(() {
                          _dragOffset = 0;
                        });
                      }
                    }
                  : null,
              child: AnimatedContainer(
                duration: _dragOffset == 0
                    ? const Duration(milliseconds: 300)
                    : Duration.zero,
                curve: Curves.easeOut,
                margin: EdgeInsets.only(left: 4 + _dragOffset),
                width: _thumbSize,
                height: _thumbSize,
                decoration: BoxDecoration(
                  color: _isConfirmed
                      ? AppColors.primary
                      : AppColors.primaryHover,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: widget.isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          _isConfirmed ? Icons.check : Icons.arrow_forward,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
