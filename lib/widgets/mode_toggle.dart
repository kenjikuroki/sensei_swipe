import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class ModeToggle extends StatelessWidget {
  final bool isSequential;
  final bool isPremium;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onLockedTap;

  const ModeToggle({
    super.key,
    required this.isSequential,
    required this.isPremium,
    required this.onModeChanged,
    required this.onLockedTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const Color selectedColor = Color(0xFF2C3E50);
    const Color unselectedColor = Colors.transparent;
    const Color selectedIconColor = Colors.white;
    const Color unselectedIconColor = Colors.black45;

    return Container(
      width: 200,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              // Shuffle Toggle
              Expanded(
                child: GestureDetector(
                  onTap: () => onModeChanged(false),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: !isSequential ? selectedColor : unselectedColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.shuffle,
                      color: !isSequential ? selectedIconColor : unselectedIconColor,
                    ),
                  ),
                ),
              ),
              // Sequential Toggle
              Expanded(
                child: GestureDetector(
                  onTap: isPremium ? () => onModeChanged(true) : onLockedTap,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSequential ? selectedColor : unselectedColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.format_list_numbered,
                          color: isSequential ? selectedIconColor : unselectedIconColor,
                        ),
                        if (!isPremium)
                          const Icon(
                            Icons.lock,
                            size: 32,
                            color: Colors.black45,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
