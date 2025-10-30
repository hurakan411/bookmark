import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリ内課金を管理するシングルトンクラス
/// 
/// 買い切り型の「広告削除」課金を処理し、購入状態を永続化します。
class PurchaseManager {
  static final PurchaseManager _instance = PurchaseManager._internal();
  factory PurchaseManager() => _instance;
  PurchaseManager._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  
  // 広告削除の課金アイテムID（App Store Connectで設定したProduct ID）
  static const String removeAdsProductId = 'remove_ads_permanent';
  
  // SharedPreferencesのキー
  static const String _purchasedKey = 'has_purchased_remove_ads';
  
  bool _isAvailable = false;
  bool _isPurchased = false;
  bool _isInitialized = false;

  /// 課金機能が利用可能かどうか
  bool get isAvailable => _isAvailable;
  
  /// 広告削除を購入済みかどうか
  bool get isPurchased => _isPurchased;
  
  /// 初期化済みかどうか
  bool get isInitialized => _isInitialized;

  /// 初期化処理
  /// 
  /// アプリ起動時に1度だけ呼び出してください。
  /// 課金機能の利用可能性チェック、購入状態の復元、購入イベントの監視を行います。
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ PurchaseManager already initialized');
      return;
    }

    try {
      // 課金機能の利用可能性チェック
      _isAvailable = await _iap.isAvailable();
      debugPrint('💳 In-App Purchase available: $_isAvailable');

      if (!_isAvailable) {
        debugPrint('⚠️ In-App Purchase not available on this device');
        _isInitialized = true;
        return;
      }

      // ローカルに保存された購入状態を読み込み
      await _loadPurchaseStatus();

      // 購入イベントのリスナーを設定
      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => debugPrint('✅ Purchase stream done'),
        onError: (error) => debugPrint('❌ Purchase stream error: $error'),
      );

      // 未完了の取引を復元
      await _restorePurchases();

      _isInitialized = true;
      debugPrint('✅ PurchaseManager initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize PurchaseManager: $e');
      _isInitialized = true; // エラーでも初期化済みとする
    }
  }

  /// 購入状態をローカルストレージから読み込み
  Future<void> _loadPurchaseStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isPurchased = prefs.getBool(_purchasedKey) ?? false;
    debugPrint('📱 Loaded purchase status: $_isPurchased');
  }

  /// 購入状態をローカルストレージに保存
  Future<void> _savePurchaseStatus(bool purchased) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_purchasedKey, purchased);
    _isPurchased = purchased;
    debugPrint('💾 Saved purchase status: $purchased');
  }

  /// 購入イベントの処理
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchaseDetails in purchaseDetailsList) {
      debugPrint('📦 Purchase update: ${purchaseDetails.productID} - ${purchaseDetails.status}');
      
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // 購入処理中
        debugPrint('⏳ Purchase pending...');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // 購入エラー
        debugPrint('❌ Purchase error: ${purchaseDetails.error}');
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                 purchaseDetails.status == PurchaseStatus.restored) {
        // 購入完了または復元完了
        if (purchaseDetails.productID == removeAdsProductId) {
          _savePurchaseStatus(true);
          debugPrint('✅ Remove ads purchase confirmed!');
        }
      }

      // 取引を完了させる（重要！）
      if (purchaseDetails.pendingCompletePurchase) {
        _iap.completePurchase(purchaseDetails);
        debugPrint('✅ Purchase completed');
      }
    }
  }

  /// 広告削除を購入
  /// 
  /// 購入ダイアログが表示され、ユーザーが承認すると課金処理が実行されます。
  Future<bool> purchaseRemoveAds() async {
    if (!_isAvailable) {
      debugPrint('⚠️ In-App Purchase not available');
      return false;
    }

    if (_isPurchased) {
      debugPrint('⚠️ Already purchased');
      return true;
    }

    try {
      // 商品情報を取得
      final ProductDetailsResponse response = await _iap.queryProductDetails({removeAdsProductId});

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('❌ Product not found: ${response.notFoundIDs}');
        return false;
      }

      if (response.productDetails.isEmpty) {
        debugPrint('❌ No product details available');
        return false;
      }

      final productDetails = response.productDetails.first;
      debugPrint('💰 Product: ${productDetails.title} - ${productDetails.price}');

      // 購入リクエスト
      final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
      final bool success = await _iap.buyNonConsumable(purchaseParam: purchaseParam);

      if (!success) {
        debugPrint('❌ Failed to initiate purchase');
      }

      return success;
    } catch (e) {
      debugPrint('❌ Purchase error: $e');
      return false;
    }
  }

  /// 購入を復元
  /// 
  /// 機種変更時などに以前の購入を復元します。
  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      debugPrint('⚠️ In-App Purchase not available');
      return;
    }

    try {
      debugPrint('🔄 Restoring purchases...');
      await _iap.restorePurchases();
      debugPrint('✅ Restore purchases completed');
    } catch (e) {
      debugPrint('❌ Restore error: $e');
    }
  }

  /// 内部的な復元処理（初期化時に自動実行）
  Future<void> _restorePurchases() async {
    try {
      // iOSでは自動的に復元、Androidでは手動復元が必要
      if (Platform.isIOS) {
        await _iap.restorePurchases();
      }
    } catch (e) {
      debugPrint('❌ Auto restore error: $e');
    }
  }

  /// リソースの解放
  void dispose() {
    _subscription?.cancel();
    debugPrint('🗑️ PurchaseManager disposed');
  }
}
