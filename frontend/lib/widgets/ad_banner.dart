import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../main.dart' show showBannerAds;
import '../services/purchase_manager.dart';

/// AdMobバナー広告ウィジェット
/// 
/// 上部・下部に配置可能なバナー広告を表示します。
/// テスト用広告IDが設定されているため、本番環境では適切な広告IDに変更してください。
/// 
/// デバッグ用フラグ `showBannerAds` が false の場合、または広告削除を購入済みの場合は、広告を表示しません。
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  int _loadAttempts = 0;
  static const int _maxLoadAttempts = 3;

  // 広告ID設定（本番環境では変更してください）
  static const String _iosAdUnitId = 'ca-app-pub-1732522218412052/8822742920';
  static const String _androidAdUnitId = 'ca-app-pub-3940256099942544/6300978111'; // テスト用

  @override
  void initState() {
    super.initState();
    // デバッグフラグがtrueかつ広告削除未購入の場合のみ広告を読み込む
    if (showBannerAds && !PurchaseManager().isPurchased) {
      _loadAd();
    }
  }

  void _loadAd() {
    _loadAttempts++;
    
    // 既存の広告を破棄
    _bannerAd?.dispose();
    
    _bannerAd = BannerAd(
      adUnitId: Platform.isIOS ? _iosAdUnitId : _androidAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('✅ Ad loaded successfully (attempt $_loadAttempts)');
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('❌ Ad failed to load (attempt $_loadAttempts/$_maxLoadAttempts): $error');
          ad.dispose();
          
          // リトライロジック
          if (_loadAttempts < _maxLoadAttempts) {
            debugPrint('🔄 Retrying ad load in 3 seconds...');
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                _loadAd();
              }
            });
          } else {
            debugPrint('⚠️ Max retry attempts reached. Ad will not be shown.');
          }
        },
        onAdOpened: (ad) {
          debugPrint('📱 Ad opened');
        },
        onAdClosed: (ad) {
          debugPrint('❎ Ad closed');
        },
        onAdImpression: (ad) {
          debugPrint('👁️ Ad impression recorded');
        },
      ),
    );

    debugPrint('📡 Loading ad (attempt $_loadAttempts)...');
    _bannerAd!.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // デバッグフラグがfalseまたは広告削除購入済みの場合は何も表示しない
    if (!showBannerAds || PurchaseManager().isPurchased) {
      return const SizedBox.shrink();
    }
    
    if (_bannerAd == null || !_isLoaded) {
      // 読み込み中のプレースホルダーを表示
      return Container(
        alignment: Alignment.center,
        width: 320,
        height: 50,
        color: Colors.grey.shade200,
        child: _loadAttempts < _maxLoadAttempts
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const SizedBox.shrink(),
      );
    }

    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
