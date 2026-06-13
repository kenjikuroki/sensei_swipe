import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io' show Platform;
import 'purchase_manager.dart';

class PreloadedAd {
  final BannerAd ad;
  final ValueNotifier<bool> isLoaded = ValueNotifier(false);

  PreloadedAd(this.ad);

  void dispose() {
    ad.dispose();
    isLoaded.dispose();
  }
}

class AdManager {
  static final AdManager instance = AdManager._internal();
  AdManager._internal();

  final Map<String, PreloadedAd> _ads = {};

  String _adUnitId = Platform.isAndroid 
      ? 'ca-app-pub-3331079517737737/4584841019' 
      : 'ca-app-pub-3331079517737737/7128272208'; // Fallback Banner (from GAS)
      
  String _interstitialAdUnitId = Platform.isAndroid 
      ? 'ca-app-pub-3331079517737737/1958677676' 
      : 'ca-app-pub-3331079517737737/7208163254'; // Fallback Interstitial (from GAS)

  final String _testBannerAdUnitId = Platform.isAndroid 
      ? 'ca-app-pub-3940256099942544/6300978111' 
      : 'ca-app-pub-3940256099942544/2934735716';
      
  final String _testInterstitialAdUnitId = Platform.isAndroid 
      ? 'ca-app-pub-3940256099942544/1033173712' 
      : 'ca-app-pub-3940256099942544/4411468910';

  // =============== 【テストと本番の切り替え】 ===============
  // テスト用（クローズドテストなど）
  String get adUnitId => _testBannerAdUnitId; 
  String get interstitialAdUnitId => _testInterstitialAdUnitId;
  
  // 本番用（公開リリース時）
  // String get adUnitId => _adUnitId; 
  // String get interstitialAdUnitId => _interstitialAdUnitId;
  // ========================================================

  void setAdUnitIds({required String bannerId, required String interstitialId}) {
    if (bannerId.isNotEmpty) _adUnitId = bannerId;
    if (interstitialId.isNotEmpty) _interstitialAdUnitId = interstitialId;
  }
  
  // Test ID for debug (optional use)
  // final String _testAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  void preloadAd(String key) {
    if (PurchaseManager.instance.isPremium.value) return;
    if (_ads.containsKey(key)) {
      // Already preloading or loaded
      return;
    }

    // The unitId is manually controlled by the getters above
    final unitId = adUnitId;

    final ad = BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('AdManager: Ad $key loaded.');
          _ads[key]?.isLoaded.value = true;
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('AdManager: Ad $key failed to load: $err');
          ad.dispose();
          _ads.remove(key);
        },
      ),
    );

    final preloadedAd = PreloadedAd(ad);
    _ads[key] = preloadedAd;
    ad.load();
  }

  PreloadedAd? getAd(String key) {
    return _ads[key];
  }
  
  /// Returns the ad and removes it from manager (transfer ownership)
  /// If [keep] is true, it retains in manager (shared ownership/singleton usage like Home).
  PreloadedAd? consumeAd(String key, {bool keep = false}) {
    if (keep) {
      return _ads[key];
    }
    return _ads.remove(key);
  }

  // Interstitial Ad
  InterstitialAd? _interstitialAd;
  
  // Real ID from user screenshot

  void preloadInterstitial() {
    if (PurchaseManager.instance.isPremium.value) return;
    // If already loaded or loading, skip? 
    // Simplified: just try to load if null.
    if (_interstitialAd != null) return;

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId, 
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('AdManager: Interstitial loaded.');
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (err) {
          debugPrint('AdManager: Interstitial failed to load: $err');
          _interstitialAd = null;
        },
      ),
    );
  }

  /// Shows the interstitial ad if available.
  /// [onComplete] is called when the ad is dismissed or if it fails to show/load.
  void showInterstitial({required VoidCallback onComplete}) {
    if (PurchaseManager.instance.isPremium.value) {
       onComplete();
       return;
    }
    if (_interstitialAd == null) {
      debugPrint('AdManager: No interstitial ready, skipping.');
      onComplete();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('AdManager: Interstitial dismissed.');
        ad.dispose();
        _interstitialAd = null;
        onComplete();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        debugPrint('AdManager: Interstitial failed to show: $err');
        ad.dispose();
        _interstitialAd = null;
        onComplete();
      },
    );

    _interstitialAd!.show();
    // Note: don't set null here immediately, wait for callbacks
  }
  
  void disposeAll() {
    for (var ad in _ads.values) {
      ad.dispose();
    }
    _ads.clear();
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
