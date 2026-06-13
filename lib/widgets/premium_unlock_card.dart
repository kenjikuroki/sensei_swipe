import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/purchase_manager.dart';
import '../utils/responsive_helper.dart';

class PremiumUnlockCard extends StatefulWidget {
  const PremiumUnlockCard({super.key});

  @override
  State<PremiumUnlockCard> createState() => _PremiumUnlockCardState();
}

class _PremiumUnlockCardState extends State<PremiumUnlockCard> {
  bool _isProcessing = false;

  Future<void> _handlePurchase(BuildContext context) async {
    if (_isProcessing || PurchaseManager.instance.isPurchasing.value) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    setState(() {
      _isProcessing = true;
    });

    try {
      await PurchaseManager.instance.buyPremium();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<bool>(
      valueListenable: PurchaseManager.instance.isPremium,
      builder: (context, isPremium, child) {
        if (isPremium) return const SizedBox.shrink();

        return Column(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: PurchaseManager.instance.isPurchasing,
              builder: (context, isPurchasing, child) {
                final bool effectivelyLocked = _isProcessing || isPurchasing;
                
                return Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.respPadding(context, 8),
                    vertical: ResponsiveHelper.respPadding(context, 8),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9F00), Color(0xFFFFD600)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: effectivelyLocked ? null : () => _handlePurchase(context),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.respPadding(context, 12),
                          vertical: ResponsiveHelper.respPadding(context, 14),
                        ),
                        child: Row(
                          children: [
                            // Icon with circular background
                            Container(
                              padding: EdgeInsets.all(ResponsiveHelper.respPadding(context, 8)),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.stars,
                                color: Colors.white,
                                size: ResponsiveHelper.respIconSize(context, 24),
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.respPadding(context, 10)),
                            // Text section
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.premiumCardTitle,
                                    softWrap: !ResponsiveHelper.isTablet(context),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: ResponsiveHelper.respFontSize(context, 16),
                                      fontWeight: FontWeight.w900,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.premiumCardSubtitle,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: ResponsiveHelper.respFontSize(context, 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Purchase button (visual only, tap handled by InkWell)
                            AbsorbPointer(
                              child: ElevatedButton(
                                onPressed: null, // Disabled because parent handles it
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFFFF9F00),
                                  disabledBackgroundColor: Colors.white,
                                  disabledForegroundColor: const Color(0xFFFF9F00),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: const StadiumBorder(),
                                  elevation: 0,
                                ),
                                child: isPurchasing
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFFFF9F00),
                                        ),
                                      )
                                    : Text(
                                        l10n.purchase,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: ResponsiveHelper.respFontSize(context, 15),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Restore button below the card
            TextButton(
              onPressed: () => PurchaseManager.instance.restorePurchases(),
              child: Text(
                l10n.restorePurchase,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
