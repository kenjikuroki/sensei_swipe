import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../utils/ad_manager.dart';
import '../utils/purchase_manager.dart';
import 'banner_ad_placeholder.dart';

class AdBanner extends StatefulWidget {
  final String? adKey;
  // If true, the ad is not disposed when this widget is disposed (e.g. for Home screen).
  final bool keepAlive; 

  const AdBanner({
    super.key, 
    this.adKey,
    this.keepAlive = false,
  });

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  ValueNotifier<bool>? _loadingNotifier; // To track listener for cleanup
  bool _showPromotion = false;
  
  String get _adUnitId => AdManager.instance.adUnitId;
  
  @override
  void initState() {
    super.initState();
    // Check if already premium
    final isPremium = PurchaseManager.instance.isPremium.value;
    if (isPremium) {
      _showPromotion = false;
      return;
    }

    // 10% probability to show premium promotion
    _showPromotion = Random().nextDouble() < 0.1;
    
    if (!_showPromotion) {
      _initAd();
    }
  }

  void _initAd() {
    if (widget.adKey != null) {
      final preloaded = AdManager.instance.consumeAd(widget.adKey!, keep: widget.keepAlive);
      if (preloaded != null) {
        _bannerAd = preloaded.ad;
        _loadingNotifier = preloaded.isLoaded;
        _isLoaded = _loadingNotifier!.value;
        
        // Listen to further updates
        _loadingNotifier!.addListener(_onPreloadedAdChange);
        return;
      }
    }

    _loadAd();
  }
  
  void _onPreloadedAdChange() {
    if (!mounted) return;
    if (_loadingNotifier != null) {
      setState(() {
        _isLoaded = _loadingNotifier!.value;
      });
    }
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: _adUnitId, 
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('$ad loaded (fallback).');
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAd failed to load: $err');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _loadingNotifier?.removeListener(_onPreloadedAdChange);
    
    if (!widget.keepAlive) {
      _bannerAd?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PurchaseManager.instance.isPremium,
      builder: (context, isPremium, child) {
        if (isPremium) return const SizedBox.shrink();

        if (_showPromotion) {
          return _buildPromotion();
        }
        
        if (_isLoaded && _bannerAd != null) {
          return SizedBox(
            width: _bannerAd!.size.width.toDouble(),
            height: _bannerAd!.size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          );
        }
        return const BannerAdPlaceholder();
      },
    );
  }

  Widget _buildPromotion() {
    return ValueListenableBuilder<bool>(
      valueListenable: PurchaseManager.instance.isPurchasing,
      builder: (context, isPurchasing, child) {
        return InkWell(
          onTap: isPurchasing ? null : () async {
            try {
              await PurchaseManager.instance.buyPremium();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            }
          },
          child: Container(
            width: double.infinity,
            height: 60,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isPurchasing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.star, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                const Text(
                  "プレミアムプランで広告を完全非表示に！",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                if (!isPurchasing) const Icon(Icons.chevron_right, color: Colors.white, size: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
