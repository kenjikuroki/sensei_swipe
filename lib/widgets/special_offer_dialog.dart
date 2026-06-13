import 'package:flutter/material.dart';
import '../utils/purchase_manager.dart';
import '../utils/prefs_helper.dart';
import '../utils/responsive_helper.dart';
import '../models/app_data.dart';
import 'dart:convert';

class SpecialOfferDialog extends StatelessWidget {
  const SpecialOfferDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Main White Card
          Container(
            width: ResponsiveHelper.isTablet(context) ? 500 : double.infinity,
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.respPadding(context, 24),
              ResponsiveHelper.isTablet(context) ? 100 : 80,
              ResponsiveHelper.respPadding(context, 24),
              ResponsiveHelper.respPadding(context, 24),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "期間限定オファー",
                  style: TextStyle(
                    fontSize: ResponsiveHelper.respFontSize(context, 26),
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<String?>(
                  future: PrefsHelper.getAppDataCache(),
                  builder: (context, snapshot) {
                    String dateText = "期間限定特別価格！";
                    if (snapshot.hasData && snapshot.data != null) {
                      try {
                        final data = AppData.fromJson(json.decode(snapshot.data!));
                        if (data.config.saleEndDate != null) {
                          final date = data.config.saleEndDate!;
                          dateText = "${date.month}月${date.day}日まで特別価格！";
                        }
                      } catch (_) {}
                    }
                    return Text(
                      dateText,
                      style: TextStyle(
                        fontSize: ResponsiveHelper.respFontSize(context, 16),
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                FutureBuilder<String?>(
                  future: PrefsHelper.getAppDataCache(),
                  builder: (context, snapshot) {
                    int regularPrice = 390;
                    int salePrice = 190;
                    if (snapshot.hasData && snapshot.data != null) {
                      try {
                        final data = AppData.fromJson(json.decode(snapshot.data!));
                        regularPrice = data.config.regularPrice;
                        salePrice = data.config.salePrice;
                      } catch (_) {}
                    }

                    return Column(
                      children: [
                        // Price Section
                        Container(
                          padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.respPadding(context, 24),
                            horizontal: ResponsiveHelper.respPadding(context, 20),
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF9E5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFFFE082), width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "¥$regularPrice",
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.respFontSize(context, 22),
                                  color: const Color(0xFF94A3B8),
                                  decoration: TextDecoration.lineThrough,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(width: ResponsiveHelper.respPadding(context, 16)),
                              Icon(
                                Icons.chevron_right,
                                color: const Color(0xFFFFB300),
                                size: ResponsiveHelper.respIconSize(context, 24),
                              ),
                              SizedBox(width: ResponsiveHelper.respPadding(context, 16)),
                              Text(
                                "¥$salePrice",
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.respFontSize(context, 42),
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF0F172A),
                                  letterSpacing: -1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                        ValueListenableBuilder<bool>(
                          valueListenable: PurchaseManager.instance.isPurchasing,
                          builder: (context, isPurchasing, child) {
                            return Container(
                              width: double.infinity,
                              height: ResponsiveHelper.respSize(context, 64),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: [
                                  BoxShadow(
                                    color: isPurchasing ? Colors.grey.withOpacity(0.1) : Colors.orange.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: isPurchasing ? null : () async {
                                  try {
                                    await PurchaseManager.instance.buyPremium();
                                    if (context.mounted) Navigator.pop(context);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error: $e')),
                                      );
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF9800),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(32),
                                  ),
                                  disabledBackgroundColor: Colors.orange.withOpacity(0.5),
                                ),
                                child: isPurchasing
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        "今すぐ¥$salePriceで購入",
                                        style: TextStyle(
                                          fontSize: ResponsiveHelper.respFontSize(context, 20),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Secondary Button
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "いいえ、結構です",
                    style: TextStyle(
                      color: const Color(0xFF94A3B8),
                      fontSize: ResponsiveHelper.respFontSize(context, 15),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Floating Icon
          Positioned(
            top: ResponsiveHelper.isTablet(context) ? -55 : -45,
            child: Container(
              padding: EdgeInsets.all(ResponsiveHelper.respPadding(context, 22)),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFCA28), Color(0xFFFF8F00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.local_offer,
                color: Colors.white,
                size: ResponsiveHelper.respIconSize(context, 44),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
