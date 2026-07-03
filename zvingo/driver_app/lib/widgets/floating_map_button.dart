import 'package:flutter/material.dart';

/// FloatingMapButton — circular icon FAB for map interactions.
/// Port of FloatingMapButton composable.
class FloatingMapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  const FloatingMapButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        elevation: 4,
        shape: const CircleBorder(),
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurface,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
