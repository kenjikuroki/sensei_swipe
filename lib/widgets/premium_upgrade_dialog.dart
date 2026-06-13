import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/purchase_manager.dart';
import '../utils/responsive_helper.dart';

class PremiumUpgradeDialog extends StatelessWidget {
  const PremiumUpgradeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: ResponsiveHelper.isTablet(context) ? 500 : null,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with Golden Gradient
          Container(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.respPadding(context, 32),
            ),
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFB300)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.respPadding(context, 12)),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.workspace_premium,
                    color: const Color(0xFFFFB300),
                    size: ResponsiveHelper.respIconSize(context, 40),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.premiumUpgrade,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: ResponsiveHelper.respFontSize(context, 22),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Benefit List
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.respPadding(context, 24)),
            child: Column(
              children: [
                _buildBenefitRow(
                  context,
                  Icons.format_list_numbered,
                  l10n.featureSequentialTitle,
                  l10n.featureSequentialDesc,
                ),
                const SizedBox(height: 24),
                _buildBenefitRow(
                  context,
                  Icons.bookmark_rounded,
                  'ブックマーク機能の解放',
                  '気になった問題をブックマークして、あとでまとめて復習できます。',
                ),
                const SizedBox(height: 24),
                _buildBenefitRow(
                  context,
                  Icons.stay_current_portrait,
                  l10n.featureNoAdsTitle,
                  l10n.featureNoAdsDesc,
                ),
              ],
            ),
          ),
          // Buttons
          Padding(
            padding: EdgeInsets.only(
              left: ResponsiveHelper.respPadding(context, 24),
              right: ResponsiveHelper.respPadding(context, 24),
              bottom: ResponsiveHelper.respPadding(context, 24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: PurchaseManager.instance.isPurchasing,
                  builder: (context, isPurchasing, child) {
                    return ElevatedButton(
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
                        backgroundColor: const Color(0xFFF39C12),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.respPadding(context, 16),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                        shadowColor: Colors.black45,
                      ).copyWith(
                        elevation: WidgetStateProperty.resolveWith<double>(
                          (Set<WidgetState> states) {
                            if (states.contains(WidgetState.pressed)) return 0;
                            return 4;
                          },
                        ),
                      ),
                      child: isPurchasing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              l10n.purchase,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: PurchaseManager.instance.isPurchasing,
                  builder: (context, isPurchasing, child) {
                    return TextButton(
                      onPressed: isPurchasing
                          ? null
                          : () async {
                              await PurchaseManager.instance.restorePurchases();
                              if (context.mounted) Navigator.pop(context);
                            },
                      child: Text(
                        l10n.restorePurchase,
                        style: TextStyle(
                          color: isPurchasing ? Colors.grey.withValues(alpha: 0.5) : Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: PurchaseManager.instance.isPurchasing,
                  builder: (context, isPurchasing, child) {
                    return TextButton(
                      onPressed: isPurchasing ? null : () => Navigator.pop(context),
                      child: Text(
                        l10n.cancel,
                        style: TextStyle(color: isPurchasing ? Colors.grey.withValues(alpha: 0.5) : Colors.grey),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    ),
  );
}

  Widget _buildBenefitRow(BuildContext context, IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: const Color(0xFFF39C12),
          size: ResponsiveHelper.respIconSize(context, 36),
        ),
        SizedBox(width: ResponsiveHelper.respPadding(context, 20)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: ResponsiveHelper.respFontSize(context, 18),
                  color: const Color(0xFF2C3E50),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: ResponsiveHelper.respFontSize(context, 14),
                  color: Colors.grey,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
