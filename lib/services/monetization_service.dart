import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/template_model.dart';

class MonetizationService {
  MonetizationService._();

  static final MonetizationService instance = MonetizationService._();

  static const String _proMonthlyProductId = 'clipsnap_pro_monthly';
  static const String _productionAndroidBannerAdUnitId =
      'ca-app-pub-6716988454965187/9111053804';
  static const String _productionAndroidInterstitialAdUnitId =
      'ca-app-pub-6716988454965187/8470880289';
  static const String _productionAndroidRewardedAdUnitId =
      'ca-app-pub-6716988454965187/4650937239';
    static const String _testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
    static const String _testInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
    static const String _testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';

    String get _androidRewardedAdUnitId =>
      kDebugMode ? _testRewardedAdUnitId : _productionAndroidRewardedAdUnitId;

  String get bannerAdUnitId {
    if (kDebugMode) {
      return _testBannerAdUnitId;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment('IOS_BANNER_AD_UNIT_ID');
    }
    return _productionAndroidBannerAdUnitId;
  }

  String get interstitialAdUnitId {
    if (kDebugMode) {
      return _testInterstitialAdUnitId;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment('IOS_INTERSTITIAL_AD_UNIT_ID');
    }
    return _productionAndroidInterstitialAdUnitId;
  }

  final ValueNotifier<bool> isProUnlocked = ValueNotifier<bool>(false);
  final Set<String> _sessionUnlockedTemplateIds = <String>{};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  Future<void>? _initializeFuture;
  InterstitialAd? _interstitialAd;
  bool _isLoadingInterstitial = false;

  Future<void> initialize() async {
    _initializeFuture ??= _initializeInternal();
    return _initializeFuture!;
  }

  Future<void> _initializeInternal() async {
    await MobileAds.instance.initialize();

    _purchaseSub ??=
        InAppPurchase.instance.purchaseStream.listen(_handlePurchases);
    await _restorePurchases();
    _preloadInterstitialAd();
  }

  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }

  void _preloadInterstitialAd() {
    if (_isLoadingInterstitial || _interstitialAd != null) {
      return;
    }

    _isLoadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('Interstitial ad loaded successfully.');
          _isLoadingInterstitial = false;
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          debugPrint(
            'Interstitial ad failed to load '
            '(code ${error.code}): ${error.message}',
          );
          _isLoadingInterstitial = false;
        },
      ),
    );
  }

  Future<bool> showInterstitialAd() async {
    await initialize();
    final ad = _interstitialAd;
    if (ad == null) {
      _preloadInterstitialAd();
      return false;
    }

    _interstitialAd = null;
    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadInterstitialAd();
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _preloadInterstitialAd();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      },
    );
    ad.show();
    return completer.future;
  }

  Future<bool> promptRewardedGate() async {
    return promptRewardedGateWithPolicy(allowOnAdLoadFailure: true);
  }

  Future<bool> promptRewardedGateWithPolicy({
    required bool allowOnAdLoadFailure,
  }) async {
    await initialize();
    final completer = Completer<bool>();

    RewardedAd.load(
      adUnitId: _androidRewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('Rewarded ad loaded successfully.');
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) {
                completer.complete(false);
              }
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!completer.isCompleted) {
                completer.complete(false);
              }
            },
          );
          ad.show(
            onUserEarnedReward: (_, __) {
              if (!completer.isCompleted) {
                completer.complete(true);
              }
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint(
            'Rewarded ad failed to load '
            '(code ${error.code}): ${error.message}',
          );
          if (!completer.isCompleted) {
            completer.complete(allowOnAdLoadFailure);
          }
        },
      ),
    );

    return completer.future;
  }

  bool isTemplateUnlocked(VideoTemplate template) {
    return !template.isPremium ||
        isProUnlocked.value ||
        _sessionUnlockedTemplateIds.contains(template.id);
  }

  Future<bool> unlockTemplateForSession(
    BuildContext context, {
    required VideoTemplate template,
  }) async {
    if (isTemplateUnlocked(template)) {
      return true;
    }

    final shouldWatch = await _showRewardedUnlockChoice(
      context,
      featureName: template.name,
    );
    if (!shouldWatch) {
      return false;
    }

    final rewarded = await promptRewardedGateWithPolicy(
      allowOnAdLoadFailure: false,
    );
    if (rewarded) {
      _sessionUnlockedTemplateIds.add(template.id);
      return true;
    }

    if (context.mounted) {
      _showSubscriptionBottomSheet(context, featureName: template.name);
    }
    return false;
  }

  Future<bool> _showRewardedUnlockChoice(
    BuildContext context, {
    required String featureName,
  }) async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF151520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unlock $featureName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Watch one short rewarded ad to use this high-end template for this session.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                    ),
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    icon: const Icon(Icons.play_circle_outline,
                        color: Colors.white),
                    label: const Text(
                      'Watch ad to unlock',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
    return choice == true;
  }

  Future<bool> unlockProFeatureGate(
    BuildContext context, {
    required String featureName,
  }) async {
    if (isProUnlocked.value) {
      return true;
    }

    final rewarded = await promptRewardedGateWithPolicy(
      allowOnAdLoadFailure: false,
    );
    if (rewarded) {
      return true;
    }

    if (context.mounted) {
      _showSubscriptionBottomSheet(context, featureName: featureName);
    }
    return false;
  }

  Future<void> triggerProFeature(
    BuildContext context,
    VoidCallback onUnlocked, {
    required String featureName,
  }) async {
    final unlocked = await unlockProFeatureGate(
      context,
      featureName: featureName,
    );
    if (unlocked) {
      onUnlocked();
    }
  }

  void _showSubscriptionBottomSheet(
    BuildContext context, {
    required String featureName,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF151520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$featureName is a ClipSnap Pro feature',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Watch a rewarded ad to unlock once, or subscribe for unlimited access.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                    ),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      startProPurchaseFlow();
                    },
                    icon: const Icon(Icons.workspace_premium,
                        color: Colors.white),
                    label: const Text(
                      'Unlock ClipSnap Pro',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> startProPurchaseFlow() async {
    await initialize();
    final productResponse = await InAppPurchase.instance.queryProductDetails(
      {_proMonthlyProductId},
    );
    if (productResponse.notFoundIDs.isNotEmpty ||
        productResponse.productDetails.isEmpty) {
      return;
    }

    final details = productResponse.productDetails.first;
    final purchaseParam = PurchaseParam(productDetails: details);
    await InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _restorePurchases() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      return;
    }
    await InAppPurchase.instance.restorePurchases();
  }

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.productID != _proMonthlyProductId) {
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        isProUnlocked.value = true;
      }

      if (purchase.pendingCompletePurchase) {
        InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }
}
