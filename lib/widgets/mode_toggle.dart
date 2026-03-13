import 'package:flutter/material.dart';
import 'premium_upgrade_dialog.dart';

enum QuizMode { shuffle, sequential }

class ModeToggle extends StatelessWidget {
  final QuizMode currentMode;
  final ValueChanged<QuizMode> onModeChanged;
  final bool isPremium;

  const ModeToggle({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 200,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: currentMode == QuizMode.shuffle
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Container(
                width: 100,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C3E50),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => onModeChanged(QuizMode.shuffle),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
                    child: Center(
                      child: Icon(
                        Icons.shuffle,
                        color: currentMode == QuizMode.shuffle
                            ? Colors.white
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (isPremium) {
                        onModeChanged(QuizMode.sequential);
                      } else {
                        showDialog(
                          context: context,
                          builder: (context) => const PremiumUpgradeDialog(),
                        );
                      }
                    },
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.format_list_numbered,
                            color: currentMode == QuizMode.sequential
                                ? Colors.white
                                : Colors.grey.shade600,
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
      ),
    );
  }
}
