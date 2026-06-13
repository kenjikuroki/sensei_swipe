import 'package:flutter/material.dart';

class PillModeToggle extends StatelessWidget {
  final bool isSequential;
  final bool isPremium;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onLockedTap;

  const PillModeToggle({
    super.key,
    required this.isSequential,
    required this.isPremium,
    required this.onModeChanged,
    required this.onLockedTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color navy = Color(0xFF2C3E50);
    const double toggleWidth = 140.0;
    const double toggleHeight = 44.0;
    // Padding around the slider is 2px
    const double sliderWidth = (toggleWidth - 4) / 2;

    return Container(
      width: toggleWidth,
      height: toggleHeight,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(toggleHeight / 2),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background Slider
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            left: isSequential ? sliderWidth : 0,
            top: 0,
            bottom: 0,
            width: sliderWidth,
            child: Container(
              decoration: BoxDecoration(
                color: navy,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: navy.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          // Transparent buttons for interaction
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => onModeChanged(false),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Icon(
                      Icons.shuffle,
                      color: !isSequential ? Colors.white : Colors.grey[500],
                      size: 20,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (isPremium) {
                      onModeChanged(true);
                    } else {
                      onLockedTap();
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.format_list_numbered,
                          color: isSequential ? Colors.white : Colors.grey[500],
                          size: 20,
                        ),
                        if (!isPremium)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.lock,
                                  size: 24,
                                  color: Colors.black.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
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
