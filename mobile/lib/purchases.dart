import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'store.dart';

const vipProductId = 'dentstudy_vip_lifetime_1990';

class VipPurchases extends ChangeNotifier {
  final InAppPurchase _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  ProductDetails? product;
  StudyStore? _study;
  bool available = false;
  bool loading = false;
  String message = '正在连接应用商店…';

  String get price => product?.price ?? '¥19.90';

  Future<void> init(StudyStore study) async {
    _study = study;
    _subscription =
        _store.purchaseStream.listen(_handlePurchases, onError: (Object error) {
      loading = false;
      message = '应用商店暂时不可用：$error';
      notifyListeners();
    });
    try {
      available = await _store.isAvailable();
      if (!available) {
        message = kIsWeb ? '请在 Android 或 iPhone App 内购买' : '当前设备无法连接应用商店';
        notifyListeners();
        return;
      }
      final response = await _store.queryProductDetails({vipProductId});
      if (response.productDetails.isEmpty) {
        message = 'VIP 商品尚未在应用商店配置';
      } else {
        product = response.productDetails.first;
        message = '一次购买，解锁每日 5000 道';
      }
    } catch (error) {
      available = false;
      message = '应用商店暂时不可用：$error';
    }
    notifyListeners();
  }

  Future<void> buy() async {
    final item = product;
    if (!available || item == null) throw Exception(message);
    loading = true;
    message = '等待应用商店确认付款…';
    notifyListeners();
    final started = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: item));
    if (!started) {
      loading = false;
      message = '未能打开付款页面，请稍后重试';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    if (!available) throw Exception(message);
    loading = true;
    message = '正在恢复购买…';
    notifyListeners();
    await _store.restorePurchases();
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != vipProductId) continue;
      if (purchase.status == PurchaseStatus.pending) {
        loading = true;
        message = '付款处理中…';
      } else if (purchase.status == PurchaseStatus.error) {
        loading = false;
        message = purchase.error?.message ?? '付款失败，请重试';
      } else if (purchase.status == PurchaseStatus.canceled) {
        loading = false;
        message = '已取消付款';
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        // StoreKit / Play Billing has accepted the transaction. A production
        // release should additionally verify its receipt on the server.
        await _study?.activateVip(purchase.purchaseID ??
            purchase.verificationData.serverVerificationData.hashCode
                .toString());
        loading = false;
        message = 'VIP 已生效，每日可刷 5000 道';
      }
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
