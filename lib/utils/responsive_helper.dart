import 'package:flutter/material.dart';

class ResponsiveHelper {
  /// Tablet breakpoint based on the shortest side of the screen.
  /// Standard Flutter/Material breakpoint for tablets is often 600.
  static const double tabletBreakpoint = 600;

  /// Returns true if the device is a tablet/iPad.
  /// Detects physical device using screen size even if running in Slide Over / Split View.
  static bool isTablet(BuildContext context) {
    // Standard window check
    if (MediaQuery.of(context).size.shortestSide >= tabletBreakpoint) return true;
    
    // Physical screen check (Detect iPad even when narrow window)
    try {
      final window = View.of(context);
      final physicalSize = window.display.size;
      final pixelRatio = window.display.devicePixelRatio;
      final logicalShortestSide = physicalSize.shortestSide / pixelRatio;
      return logicalShortestSide >= 600;
    } catch (_) {
      return false;
    }
  }

  /// Scale factor for tablet devices.
  /// User requested "about half size" (0.5), then "a bit larger" from 0.7.
  static double getScaleFactor(BuildContext context) {
    return isTablet(context) ? 0.85 : 1.0;
  }

  /// Returns a responsive font size based on the base size.
  static double respFontSize(BuildContext context, double baseSize) {
    return baseSize * getScaleFactor(context);
  }

  /// Returns a responsive icon size based on the base size.
  static double respIconSize(BuildContext context, double baseSize) {
    return baseSize * getScaleFactor(context);
  }

  /// Returns a responsive horizontal/vertical padding or margin.
  static double respPadding(BuildContext context, double basePadding) {
    // For tablets, make it much more compact as requested
    return isTablet(context) ? basePadding * 0.7 : basePadding;
  }

  /// Returns a responsive width or height.
  static double respSize(BuildContext context, double baseSize) {
    return baseSize * getScaleFactor(context);
  }

  /// Returns a maximum width for cards to prevent stretching on tablets.
  static double? respCardWidth(BuildContext context) {
    return isTablet(context) ? 600 : null;
  }
}
