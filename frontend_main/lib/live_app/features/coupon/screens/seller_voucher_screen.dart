// =============================================================================
// seller_voucher_screen.dart
// =============================================================================
// Seller: quản lý + tạo Voucher của shop ("Mua với Voucher"). Voucher áp ở
// bước thanh toán bằng cơ chế coupon order-level sẵn có.
//   - [SellerVoucherScreen]: danh sách voucher của shop
//   - [CreateVoucherScreen]: form tạo voucher mới (public — dùng lại ở picker
//     coupon khi đăng video)
// =============================================================================

import 'package:flutter/material.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/coupon/data/coupon_repository.dart';

String _fmtVnd(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  buf.write('đ');
  return buf.toString();
}

String _fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

class SellerVoucherScreen extends StatefulWidget {
  const SellerVoucherScreen({super.key});

  @override
  State<SellerVoucherScreen> createState() => _SellerVoucherScreenState();
}

class _SellerVoucherScreenState extends State<SellerVoucherScreen> {
  final _repo = CouponRepository.instance;
  List<CouponModel> _vouchers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.listMine();
      if (mounted) setState(() => _vouchers = list);
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<CouponModel>(
      MaterialPageRoute(builder: (_) => const CreateVoucherScreen()),
    );
    if (created != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voucher của Shop'),
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tạo voucher'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.secondary),
              )
            : _error != null
            ? _centered(
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              )
            : _vouchers.isEmpty
            ? _centered(
                const Text(
                  'Chưa có voucher — bấm "Tạo voucher"',
                  style: TextStyle(color: AppColors.textHint),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSizes.md),
                itemCount: _vouchers.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSizes.sm),
                itemBuilder: (_, i) => _VoucherCard(coupon: _vouchers[i]),
              ),
      ),
    );
  }

  Widget _centered(Widget child) => ListView(
    children: [
      const SizedBox(height: 160),
      Center(child: child),
    ],
  );
}

class _VoucherCard extends StatelessWidget {
  final CouponModel coupon;
  const _VoucherCard({required this.coupon});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              ),
              child: const Icon(Icons.local_offer, color: AppColors.secondary),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        coupon.discountLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusSm,
                          ),
                        ),
                        child: Text(
                          coupon.code,
                          style: const TextStyle(
                            fontSize: AppSizes.fontXs,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${coupon.minOrderValue > 0 ? 'Đơn từ ${_fmtVnd(coupon.minOrderValue)}  •  ' : ''}HSD ${_fmtDate(coupon.expiresAt)}',
                    style: const TextStyle(
                      fontSize: AppSizes.fontXs,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Form tạo voucher shop. Trả về [CouponModel] vừa tạo qua Navigator.pop (null
/// nếu huỷ) để màn gọi vừa reload danh sách vừa có thể tự chọn coupon mới (dùng
/// chung cho cả màn "Voucher của Shop" lẫn picker coupon khi đăng video).
class CreateVoucherScreen extends StatefulWidget {
  const CreateVoucherScreen({super.key});

  @override
  State<CreateVoucherScreen> createState() => _CreateVoucherScreenState();
}

class _CreateVoucherScreenState extends State<CreateVoucherScreen> {
  final _repo = CouponRepository.instance;
  final _codeCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _minOrderCtrl = TextEditingController();
  final _maxDiscountCtrl = TextEditingController();
  final _maxUsesCtrl = TextEditingController();
  String _type = 'percent';
  late DateTime _expiresAt = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _minOrderCtrl.dispose();
    _maxDiscountCtrl.dispose();
    _maxUsesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null)
      setState(
        () => _expiresAt = DateTime(date.year, date.month, date.day, 23, 59),
      );
  }

  void _err(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final value = double.tryParse(_valueCtrl.text.trim());
    if (code.length < 2) return _err('Mã voucher tối thiểu 2 ký tự');
    if (value == null || value <= 0) return _err('Giá trị giảm không hợp lệ');
    if (_type == 'percent' && value > 100)
      return _err('Phần trăm giảm tối đa 100');
    final minOrder = double.tryParse(_minOrderCtrl.text.trim()) ?? 0;
    final maxDiscount = _maxDiscountCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_maxDiscountCtrl.text.trim());
    final maxUses = _maxUsesCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_maxUsesCtrl.text.trim());

    setState(() => _saving = true);
    try {
      final created = await _repo.createShopVoucher(
        code: code,
        discountType: _type,
        discountValue: value,
        minOrderValue: minOrder,
        maxDiscount: maxDiscount,
        maxUses: maxUses,
        expiresAt: _expiresAt,
      );
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _err(AuthService.errorMessage(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo Voucher'),
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.md),
        children: [
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Mã voucher (VD: SHOP50K)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'percent',
                  groupValue: _type,
                  title: const Text('Theo %'),
                  activeColor: AppColors.secondary,
                  onChanged: (v) => setState(() => _type = v!),
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'fixed',
                  groupValue: _type,
                  title: const Text('Số tiền'),
                  activeColor: AppColors.secondary,
                  onChanged: (v) => setState(() => _type = v!),
                ),
              ),
            ],
          ),
          TextField(
            controller: _valueCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _type == 'percent'
                  ? 'Phần trăm giảm (%)'
                  : 'Số tiền giảm (đ)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _minOrderCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Giá trị đơn tối thiểu (đ) — để trống = 0',
              border: OutlineInputBorder(),
            ),
          ),
          if (_type == 'percent') ...[
            const SizedBox(height: AppSizes.md),
            TextField(
              controller: _maxDiscountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Giảm tối đa (đ) — để trống = không giới hạn',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _maxUsesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số lượt tối đa — để trống = không giới hạn',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          InkWell(
            onTap: _pickExpiry,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Hạn sử dụng',
                border: OutlineInputBorder(),
              ),
              child: Text(_fmtDate(_expiresAt)),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.4,
                      ),
                    )
                  : const Text(
                      'Tạo voucher',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
