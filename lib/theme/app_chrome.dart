import 'package:flutter/material.dart';

class AppColors {
  static const Color ink = Color(0xFF223047);
  static const Color inkSoft = Color(0xFF5F7187);
  static const Color inkMuted = Color(0xFF8EA0B5);
  static const Color line = Color(0xFFCCD8E5);
  static const Color accent = Color(0xFF3D5270);
  static const Color accentSoft = Color(0xFFE8EEF8);
  static const Color accentHighlight = Color(0xFF5E86FF);
  static const Color backgroundTop = Color(0xFFEEF4FB);
  static const Color backgroundBottom = Color(0xFFD7E2EE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEBF1F8);
  static const Color success = Color(0xFF4CB35D);
  static const Color error = Color(0xFFFF5A5A);
  static const Color warning = Color(0xFFFF9D0A);
}

class AppChrome {
  static LinearGradient get pageGradient => const LinearGradient(
    colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: const Color(0xFF21314D).withValues(alpha: 0.08),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
  ];

  static List<BoxShadow> get liftShadow => [
    BoxShadow(
      color: const Color(0xFF21314D).withValues(alpha: 0.1),
      blurRadius: 34,
      offset: const Offset(0, 16),
    ),
  ];

  static ThemeData theme(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        primary: AppColors.accent,
        surface: AppColors.surface,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.backgroundTop,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.accent,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static ButtonStyle primaryButtonStyle({
    Color backgroundColor = AppColors.warning,
    Color foregroundColor = Colors.white,
    double radius = 20,
    EdgeInsetsGeometry? padding,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      elevation: 8,
      shadowColor: const Color(0xFF21314D).withValues(alpha: 0.12),
      padding: padding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE9F0F8), Color(0xFFE3EBF4), Color(0xFFDCE4EE)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.44, 1.0],
        ),
        color: AppColors.backgroundTop,
      ),
      child: child,
    );
  }
}

class SoftSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry borderRadius;
  final Color? fillColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  const SoftSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.fillColor,
    this.borderColor,
    this.boxShadow,
    this.onTap,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: fillColor ?? AppColors.surface.withValues(alpha: 0.98),
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? AppColors.line.withValues(alpha: 0.92),
          width: 1,
        ),
        boxShadow: boxShadow ?? AppChrome.softShadow,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (onTap == null) {
      return ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: clipBehavior,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
