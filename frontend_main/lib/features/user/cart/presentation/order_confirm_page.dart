import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tropia_mobile_app_android/core/constants/app_colors.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/models/cart_model.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/models/store_model.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/models/user_address_model.dart';

class OrderConfirmPage extends StatelessWidget {
  final CartModel cartData;
  final bool isDelivery;
  final UserAddressModel? selectedAddress;
  final StoreModel selectedStore;
  final String paymentMethod;
  final DateTime selectedDate;
  final String selectedTimeSlot;
  final String note;
  final double totalPayment;

  const OrderConfirmPage({
    super.key,
    required this.cartData,
    required this.isDelivery,
    required this.selectedAddress,
    required this.selectedStore,
    required this.paymentMethod,
    required this.selectedDate,
    required this.selectedTimeSlot,
    required this.note,
    required this.totalPayment,
  });

  String _paymentLabel(String method) {
    switch (method) {
      case 'bank':
      case 'transfer':
      case 'bank_transfer':
        return 'Chuyển khoản';
      case 'cod':
      default:
        return 'Thanh toán khi nhận hàng (COD)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
    final dateStr = DateFormat('dd/MM/yyyy').format(selectedDate);
    final subtotal = cartData.summary.subtotal;
    final total = totalPayment;
    final delta = total - subtotal;
    final deliveryFee = delta > 0 ? delta : 0.0;
    final discount = delta < 0 ? -delta : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Xác nhận đơn hàng',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _SectionCard(
                    title: 'Thông tin nhận hàng',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _KeyValueRow(
                          label: 'Hình thức',
                          value: isDelivery
                              ? 'Giao hàng tận nơi'
                              : 'Nhận tại cửa hàng',
                        ),
                        const SizedBox(height: 8),
                        if (isDelivery) ...[
                          _KeyValueRow(
                            label: 'Cửa hàng',
                            value: selectedStore.storeName,
                          ),
                          const SizedBox(height: 6),
                          _KeyValueRow(
                            label: 'Địa chỉ cửa hàng',
                            value: selectedStore.storeAddress,
                          ),
                          const Divider(height: 20),
                          _KeyValueRow(
                            label: 'Người nhận',
                            value:
                                (selectedAddress?.receiverName ?? '')
                                    .trim()
                                    .isEmpty
                                ? '—'
                                : selectedAddress!.receiverName,
                          ),
                          const SizedBox(height: 6),
                          _KeyValueRow(
                            label: 'SĐT',
                            value: (selectedAddress?.phone ?? '').trim().isEmpty
                                ? '—'
                                : selectedAddress!.phone,
                          ),
                          const SizedBox(height: 6),
                          _KeyValueRow(
                            label: 'Địa chỉ giao',
                            value:
                                (selectedAddress?.fullAddress ?? '')
                                    .trim()
                                    .isEmpty
                                ? '—'
                                : selectedAddress!.fullAddress,
                          ),
                        ] else ...[
                          _KeyValueRow(
                            label: 'Cửa hàng',
                            value: selectedStore.storeName,
                          ),
                          const SizedBox(height: 6),
                          _KeyValueRow(
                            label: 'Địa chỉ cửa hàng',
                            value: selectedStore.storeAddress,
                          ),
                        ],
                        const Divider(height: 20),
                        _KeyValueRow(
                          label: 'Thời gian',
                          value: '$dateStr | $selectedTimeSlot',
                        ),
                        const SizedBox(height: 6),
                        _KeyValueRow(
                          label: 'Thanh toán',
                          value: _paymentLabel(paymentMethod),
                        ),
                        if (note.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _KeyValueRow(label: 'Ghi chú', value: note.trim()),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Chi tiết hóa đơn',
                    child: Column(
                      children: [
                        ...cartData.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item.quantity} x ${currencyFormat.format(item.price)}',
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  currencyFormat.format(item.totalLinePrice),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 20),
                        _KeyValueRow(
                          label: 'Tạm tính',
                          value: currencyFormat.format(subtotal),
                        ),
                        if (discount > 0) ...[
                          const SizedBox(height: 6),
                          _KeyValueRow(
                            label: 'Giảm giá',
                            value: '-${currencyFormat.format(discount)}',
                          ),
                        ],
                        if (deliveryFee > 0) ...[
                          const SizedBox(height: 6),
                          _KeyValueRow(
                            label: 'Phí giao hàng',
                            value: currencyFormat.format(deliveryFee),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _KeyValueRow(
                          label: 'Tổng thanh toán',
                          value: currencyFormat.format(total),
                          isEmphasis: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              12,
              10,
              12,
              12 + MediaQuery.of(context).viewPadding.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Quay lại'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Xác nhận đặt hàng',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isEmphasis;

  const _KeyValueRow({
    required this.label,
    required this.value,
    this.isEmphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: isEmphasis ? 15 : 13,
              fontWeight: isEmphasis ? FontWeight.bold : FontWeight.w600,
              color: isEmphasis ? AppColors.primary : Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}
