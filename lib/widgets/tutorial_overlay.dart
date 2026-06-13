import 'package:flutter/material.dart';

class TutorialOverlay extends StatelessWidget {
  final VoidCallback onDismiss;

  const TutorialOverlay({
    super.key,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Material(
        color: Colors.black.withOpacity(0.75),
        child: Stack(
          children: [
            // Center Message
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  '左右にスワイプして回答',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: Colors.black.withOpacity(0.5),
                        offset: const Offset(2.0, 2.0),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Left Guide
            Positioned(
              left: 40,
              bottom: 120,
              child: Column(
                children: [
                  const Icon(
                    Icons.keyboard_double_arrow_left_rounded,
                    color: Colors.redAccent,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '× 誤り',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Right Guide
            Positioned(
              right: 40,
              bottom: 120,
              child: Column(
                children: [
                  const Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    color: Colors.greenAccent,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '○ 正しい',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),

            // Start Button
            Positioned(
              left: 40,
              right: 40,
              bottom: 40,
              child: Center(
                child: SizedBox(
                  width: 200,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      shape: const StadiumBorder(),
                      elevation: 0,
                    ),
                    child: const Text(
                      'はじめる',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
