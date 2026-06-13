import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_manager.dart';
import 'prefs_helper.dart';
import '../models/app_data.dart';
import 'dart:convert';

class PurchaseManager {
  static final PurchaseManager instance = PurchaseManager._internal();
  PurchaseManager._internal();

  String _productId = 'unlock_premium';

  bool _isValidProductId(String id) {
    final normalized = id.trim().toLowerCase();
    return normalized.isNotEmpty && normalized != 'nan' && normalized != 'null';
  }

  String get productId {
    return _productId;
  }

  static const String _prefsKeyPremium = 'is_premium';
  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  final ValueNotifier<bool> isPremium = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isPurchasing = ValueNotifier<bool>(false);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    isPremium.value = prefs.getBool(_prefsKeyPremium) ?? false;

    if (isPremium.value) {
      AdManager.instance.disposeAll();
    }

    final Stream purchaseUpdated = _iap.purchaseStream;
    _subscription =
        purchaseUpdated.listen(
              (purchaseDetailsList) {
                _listenToPurchaseUpdated(purchaseDetailsList);
              },
              onDone: () {
                _subscription.cancel();
              },
              onError: (error) {
                debugPrint('PurchaseManager Error: $error');
              },
            )
            as StreamSubscription<List<PurchaseDetails>>;

    await _queryProducts();
  }

  Future<void> _queryProducts() async {
    try {
      _isAvailable = await _iap.isAvailable();
      if (_isAvailable) {
        Set<String> ids = {productId};
        final ProductDetailsResponse response = await _iap.queryProductDetails(
          ids,
        );
        if (response.error == null) {
          _products = response.productDetails;
          debugPrint(
            'PurchaseManager: Loaded ${_products.length} products for $productId',
          );
        } else {
          debugPrint(
            'PurchaseManager Error querying products: ${response.error}',
          );
        }
      }
    } catch (e) {
      debugPrint('PurchaseManager Exception in _queryProducts: $e');
    }
  }

  void setProductId(String id) {
    if (_isValidProductId(id) && id != _productId) {
      debugPrint(
        'PurchaseManager: Updating product ID from $_productId to $id',
      );
      _productId = id;
      _queryProducts();
    } else if (!_isValidProductId(id)) {
      debugPrint(
        'PurchaseManager: Ignoring invalid product ID "$id", keeping $_productId',
      );
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Show pending UI if needed
      } else {
        if (purchaseDetails.status == PurchaseStatus.error ||
            purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored ||
            purchaseDetails.status == PurchaseStatus.canceled) {
          isPurchasing.value = false;
        }

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
    if (isPurchasing.value) return;
    isPurchasing.value = true;

    try {
      if (!_isAvailable || _products.isEmpty) {
        debugPrint('PurchaseManager: Products not ready, re-querying...');
        await _queryProducts();
      }

      if (!_isAvailable) {
        debugPrint('PurchaseManager: IAP not available');
        throw Exception('In-app purchase is not available on this device.');
      }

      if (_products.isEmpty) {
        debugPrint(
          'PurchaseManager Error: Could not load product details for $productId',
        );
        throw Exception(
          'Product details for "$productId" could not be loaded. Please check your internet connection or Store settings.',
        );
      }

      ProductDetails? product;
      for (var p in _products) {
        if (p.id == productId) {
          product = p;
          break;
        }
      }

      // Fallback to first product if specific ID not found
      product ??= _products.first;

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
      );
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      isPurchasing.value = false;
      debugPrint('PurchaseManager Exception in buyPremium: $e');
      throw Exception('An unexpected error occurred during purchase: $e');
    }
    // Note: isPurchasing.value = false is handled in _listenToPurchaseUpdated
    // when the status changes to purchased, restored, or error.
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  /// Check if the special offer should be shown.
  Future<bool> shouldShowSpecialOffer() async {
    if (isPremium.value) return false;

    final cachedJson = await PrefsHelper.getAppDataCache();
    if (cachedJson == null) return false;

    final appData = AppData.fromJson(json.decode(cachedJson));
    if (!appData.config.isSaleActive) return false;

    final alreadyShown = await PrefsHelper.isSpecialOfferShown();
    if (alreadyShown) return false;

    return true;
  }

  Future<void> markSpecialOfferAsShown() async {
    await PrefsHelper.markSpecialOfferShown();
  }

  void dispose() {
    _subscription.cancel();
  }
}
