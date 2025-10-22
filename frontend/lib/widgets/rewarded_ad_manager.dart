import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedAdManager {
  static RewardedAd? _rewardedAd;
  static bool _isLoaded = false;

  static const String _iosAdUnitId = 'ca-app-pub-3940256099942544/1712485313'; // テスト用
  static const String _androidAdUnitId = 'ca-app-pub-3940256099942544/5224354917'; // テスト用

  static Future<void> loadAd() async {
    _rewardedAd = null;
    _isLoaded = false;
    
    final completer = Completer<void>();
    
    RewardedAd.load(
      adUnitId: Platform.isIOS ? _iosAdUnitId : _androidAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('✅ RewardedAd loaded successfully');
          _rewardedAd = ad;
          _isLoaded = true;
          completer.complete();
        },
        onAdFailedToLoad: (error) {
          debugPrint('❌ RewardedAd failed to load: $error');
          _isLoaded = false;
          completer.complete();
        },
      ),
    );
    
    return completer.future;
  }

  static Future<bool> showAd() async {
    if (_rewardedAd == null && !_isLoaded) {
      await loadAd();
    }
    
    if (_rewardedAd == null) {
      debugPrint('⚠️ RewardedAd not available');
      return false;
    }
    
    final completer = Completer<bool>();
    bool rewarded = false;
    
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('📱 RewardedAd dismissed, rewarded: $rewarded');
        ad.dispose();
        _rewardedAd = null;
        _isLoaded = false;
        
        // 次回用に広告を再読み込み
        loadAd();
        
        // 報酬獲得状態を返す
        completer.complete(rewarded);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('❌ RewardedAd failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        _isLoaded = false;
        
        // 次回用に広告を再読み込み
        loadAd();
        
        completer.complete(false);
      },
    );
    
    _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
      debugPrint('🎁 User earned reward: ${reward.amount} ${reward.type}');
      rewarded = true;
    });
    
    return completer.future;
  }

  static bool get isLoaded => _isLoaded;
}
