import '../../domain/entities/store_purchase.dart';

/// [StorePurchase] come viaggia verso `POST /paywall/purchase`:
/// `{"platform": "ios"|"android"|"fake", "productId", "receipt",
/// "transactionId"}` (protocollo in `server/routes/paywall/purchase.dart`).
class StorePurchaseModel extends StorePurchase {
  const StorePurchaseModel({
    required super.platform,
    required super.productId,
    required super.transactionId,
    required super.verificationData,
  });

  factory StorePurchaseModel.fromEntity(StorePurchase purchase) =>
      StorePurchaseModel(
        platform: purchase.platform,
        productId: purchase.productId,
        transactionId: purchase.transactionId,
        verificationData: purchase.verificationData,
      );

  Map<String, dynamic> toJson() => {
    'platform': switch (platform) {
      StorePlatform.appStore => 'ios',
      StorePlatform.googlePlay => 'android',
      StorePlatform.fake => 'fake',
    },
    'productId': productId,
    'receipt': verificationData,
    'transactionId': transactionId,
  };
}
