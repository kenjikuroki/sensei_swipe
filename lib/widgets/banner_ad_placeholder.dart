import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class BannerAdPlaceholder extends StatelessWidget {
  const BannerAdPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60, // Standard banner height
      color: Colors.white, // Background for the banner area
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
             border: Border.all(color: Colors.grey[300]!),
          ),
           // Just a blank shimmering box as requested
        ),
      ),
    );
  }
}
