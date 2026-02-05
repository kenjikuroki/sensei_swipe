import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_manager.dart';
import 'prefs_helper.dart';

class PurchaseManager {
  static final PurchaseManager instance = PurchaseManager._internal();
  PurchaseManager._internal();

  static const String productId = 'unlock_premium';
  static const String _prefsKeyPremium = 'is_premium_unlocked';
  static const String _prefsKeyOfferShown = 'special_offer_shown';

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  final ValueNotifier<bool> isPremium = ValueNotifier<bool>(false);
  
  bool _isAvailable = false;
  List<ProductDetails> _products = [];

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    isPremium.value = prefs.getBool(_prefsKeyPremium) ?? false;

    if (isPremium.value) {
      AdManager.instance.disposeAll();
    }

    final Stream purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      debugPrint('PurchaseManager Error: $error');
    }) as StreamSubscription<List<PurchaseDetails>>;

    _isAvailable = await _iap.isAvailable();
    if (_isAvailable) {
      const Set<String> ids = {productId};
      final ProductDetailsResponse response = await _iap.queryProductDetails(ids);
      if (response.error == null) {
        _products = response.productDetails;
      }
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Show pending UI if needed
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          debugPrint('Purchase Error: ${purchaseDetails.error}');
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          _unlockPremium();
        }
        if (purchaseDetails.pendingCompletePurchase) {
          _iap.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future<void> _unlockPremium() async {
    isPremium.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyPremium, true);
    AdManager.instance.disposeAll();
    debugPrint('Premium unlocked!');
  }

  Future<void> buyPremium() async {
    if (!_isAvailable) return;
    final product = _products.firstWhere((p) => p.id == productId);
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  /// Check if the special offer should be shown.
  Future<bool> shouldShowSpecialOffer() async {
    if (isPremium.value) return false;

    // Show Condition:
    // 1. User is NOT premium (checked above)
    // 2. Offer has NOT been shown before (new key v1)
    // 3. Date is before March 1, 2026.
    
    final alreadyShown = await PrefsHelper.isSpecialOfferShown();
    if (alreadyShown) return false;

    // Deadline: March 1st, 2026.
    final limitDate = DateTime(2026, 3, 1);
    final now = DateTime.now();
    
    return now.isBefore(limitDate);
  }

  Future<void> markSpecialOfferAsShown() async {
    await PrefsHelper.markSpecialOfferShown();
  }

  void dispose() {
    _subscription.cancel();
  }
}
