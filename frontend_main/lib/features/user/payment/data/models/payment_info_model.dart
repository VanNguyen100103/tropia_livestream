class PaymentInfoModel {
  final String payUrl;
  final String qrCodeUrl;
  final String orderId;
  final String requestId;

  const PaymentInfoModel({
    required this.payUrl,
    required this.qrCodeUrl,
    required this.orderId,
    required this.requestId,
  });

  factory PaymentInfoModel.fromJson(Map<String, dynamic> json) {
    return PaymentInfoModel(
      payUrl: json['pay_url']?.toString() ?? '',
      qrCodeUrl: json['qr_code_url']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      requestId: json['request_id']?.toString() ?? '',
    );
  }

  // Backend có thể không trả qr_code_url hoặc request_id trong một số môi trường.
  bool get isValid => payUrl.isNotEmpty && orderId.isNotEmpty;
}
