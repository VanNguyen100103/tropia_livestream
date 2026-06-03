import 'package:dio/dio.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';

import '../data/datasources/payment_remote_datasource.dart';
import '../data/models/payment_info_model.dart';

class PaymentPage extends StatefulWidget {
  final PaymentInfoModel paymentInfo;
  final Map<String, dynamic> pendingCheckoutPayload;

  const PaymentPage({
    super.key,
    required this.paymentInfo,
    required this.pendingCheckoutPayload,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  late final Dio _dio;
  late final PaymentRemoteDataSource _paymentDs;
  late final CartRemoteDataSource _cartDs;

  bool _isCheckingPayment = false;
  bool _isFinalizingOrder = false;
  bool _isPaid = false;
  bool _hasFinalizedCheckout = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _dio = DioClient().dio;
    _paymentDs = PaymentRemoteDataSourceImpl(client: _dio);
    _cartDs = CartRemoteDataSourceImpl(client: _dio);
  }

  bool _isPaymentSuccess(Map<String, dynamic> statusRes) {
    final data = statusRes['data'];
    final dynamic resultCode = (data is Map) ? data['result_code'] : null;
    final int? resultCodeInt = int.tryParse(resultCode?.toString() ?? '');
    if (resultCodeInt == 0) return true;

    final String message =
        ((data is Map ? data['message'] : null) ??
                statusRes['StatusMess'] ??
                statusRes['message'] ??
                '')
            .toString()
            .toLowerCase();

    return message.contains('success') ||
        message.contains('thành công') ||
        message.contains('thanh cong');
  }

  Future<void> _checkPayment() async {
    if (_isCheckingPayment || _isFinalizingOrder) return;
    setState(() {
      _isCheckingPayment = true;
      _statusMessage = '';
    });

    try {
      final res = await _paymentDs.checkPaymentStatus(
        orderId: widget.paymentInfo.orderId,
        requestId: widget.paymentInfo.requestId,
      );

      if (!mounted) return;

      if (res == null) {
        setState(() {
          _statusMessage = 'Không nhận được phản hồi trạng thái thanh toán.';
          _isPaid = false;
        });
        return;
      }

      final ok = _isPaymentSuccess(res);
      final data = res['data'];
      final message =
          (data is Map ? data['message'] : null) ??
          res['StatusMess'] ??
          res['message'] ??
          '';

      setState(() {
        _isPaid = ok;
        _statusMessage = ok
            ? 'Thanh toán thành công. Bạn có thể tạo đơn hàng.'
            : 'Chưa thanh toán / thất bại: $message';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPaid = false;
        _statusMessage = 'Lỗi khi kiểm tra thanh toán: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isCheckingPayment = false);
      }
    }
  }

  Future<void> _finalizeOrder() async {
    if (_isFinalizingOrder || _isCheckingPayment) return;
    if (_hasFinalizedCheckout) return;
    if (!_isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng kiểm tra thanh toán thành công trước.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isFinalizingOrder = true;
      _statusMessage = '';
      _hasFinalizedCheckout = true;
    });

    try {
      debugPrint('🚀 [API REQUEST] order-checkout (bank_transfer)');
      final res = await _cartDs.checkout(widget.pendingCheckoutPayload);

      if (!mounted) return;

      final ok = res != null && (res['Result'] == true || res['status'] == 200);
      if (!ok) {
        final err =
            (res?['StatusMess'] ?? res?['message'] ?? 'Checkout thất bại')
                .toString();
        setState(() {
          _statusMessage = err;
          _hasFinalizedCheckout = false; // allow retry
        });
        return;
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Lỗi khi tạo đơn: $e';
        _hasFinalizedCheckout = false;
      });
    } finally {
      if (mounted) setState(() => _isFinalizingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isCheckingPayment || _isFinalizingOrder;
    final qrCodeUrl = widget.paymentInfo.qrCodeUrl;
    final payUrl = widget.paymentInfo.payUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('Thanh toán MoMo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Quét QR để thanh toán',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: qrCodeUrl.isNotEmpty
                      ? Image.network(
                          qrCodeUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(
                              'Không tải được QR.\nDùng QR tạo từ link ở dưới.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        )
                      : (payUrl.isNotEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: BarcodeWidget(
                                    barcode: Barcode.qrCode(),
                                    data: payUrl,
                                    drawText: false,
                                    color: Colors.black,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  'Không có link thanh toán để tạo QR.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              )),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      payUrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: payUrl));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã copy link thanh toán'),
                        ),
                      );
                    },
                    child: const Text('Copy'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_statusMessage.isNotEmpty)
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isPaid ? Colors.green : Colors.grey.shade700,
                  ),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: isBusy ? null : _checkPayment,
                child: _isCheckingPayment
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Kiểm tra thanh toán'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: isBusy ? null : _finalizeOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: _isFinalizingOrder
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Tạo đơn hàng'),
              ),
              const SizedBox(height: 8),
              Text(
                'Lưu ý: Chỉ bấm "Tạo đơn hàng" sau khi kiểm tra thanh toán thành công.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
