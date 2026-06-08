// =============================================================================
// seller_coupon_picker_screen.dart
// =============================================================================
// Picker chọn coupon (voucher shop) để gắn vào 1 video khi đăng (Shopee Video
// "Voucher"). Single-select — mỗi video chỉ gắn 1 voucher:
//   - AppBar "Chọn voucher cho video"
//   - Nút "Tạo coupon mới" đầu danh sách → mở CreateVoucherScreen, tạo xong tự
//     thêm vào list + chọn luôn.
//   - Mỗi dòng: tick-circle (trái) + thông tin coupon. Tap chọn voucher đó (bỏ
//     chọn cái cũ); tap lại dòng đang chọn để bỏ hẳn (không gắn voucher).
//   - Bottom: nút "Thêm" trả về List<CouponModel> (0 hoặc 1 phần tử).
//
// Trả selection qua Navigator.pop(List<CouponModel>); pop rỗng/null = không đổi.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/coupon/data/coupon_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/coupon/screens/seller_voucher_screen.dart';

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

class SellerCouponPickerScreen extends StatefulWidget {
  /// Coupon đã chọn trước đó (để mở lại picker giữ nguyên tick).
  final List<CouponModel> alreadySelected;

  const SellerCouponPickerScreen({super.key, this.alreadySelected = const []});

  @override
  State<SellerCouponPickerScreen> createState() =>
      _SellerCouponPickerScreenState();
}

class _SellerCouponPickerScreenState extends State<SellerCouponPickerScreen> {
  final _repo = CouponRepository.instance;

  // Danh sách coupon của shop. Coupon vừa tạo inline được chèn lên đầu.
  final List<CouponModel> _coupons = [];
  // Single-select: id của voucher đang chọn (null = chưa chọn / bỏ chọn).
  String? _selectedId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.alreadySelected.isNotEmpty
        ? widget.alreadySelected.first.id
        : null;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.listMine();
      if (!mounted) return;
      setState(() {
        // Giữ coupon vừa tạo inline (nếu có) mà chưa xuất hiện trong list mới.
        final fetchedIds = list.map((c) => c.id).toSet();
        final keptLocal = _coupons.where((c) => !fetchedIds.contains(c.id));
        _coupons
          ..clear()
          ..addAll(keptLocal)
          ..addAll(list);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthService.errorMessage(e);
      });
    }
  }

  void _select(String id) {
    setState(() {
      // Single-select: tap chọn voucher đó (bỏ cái cũ); tap lại dòng đang
      // chọn để bỏ hẳn — cho phép video không gắn voucher nào.
      _selectedId = _selectedId == id ? null : id;
    });
  }

  void _confirm() {
    final selected = _coupons.where((c) => c.id == _selectedId).toList();
    Navigator.pop(context, selected);
  }

  Future<void> _createNew() async {
    final created = await Navigator.of(context).push<CouponModel>(
      MaterialPageRoute(builder: (_) => const CreateVoucherScreen()),
    );
    if (created != null && mounted) {
      setState(() {
        _coupons.insert(0, created);
        _selectedId = created.id;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Chọn voucher cho video'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _coupons.isEmpty) return _buildError();

    // index 0 = nút tạo mới; phần còn lại là coupon.
    final total = 1 + _coupons.length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
        itemCount: total,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) {
          if (i == 0) return _buildCreateButton();
          final c = _coupons[i - 1];
          return _CouponPickerRow(
            coupon: c,
            isSelected: _selectedId == c.id,
            onTap: () => _select(c.id),
          );
        },
      ),
    );
  }

  Widget _buildCreateButton() {
    return GestureDetector(
      onTap: _createNew,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.add, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: AppSizes.sm),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tạo coupon mới',
                    style: TextStyle(
                      fontSize: AppSizes.fontMd,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'Tạo voucher cho shop rồi gắn ngay vào video',
                    style: TextStyle(
                      fontSize: AppSizes.fontXs,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final hasSelection = _selectedId != null;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        AppSizes.sm + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Chỉ chọn 1 voucher cho video',
              style: TextStyle(
                fontSize: AppSizes.fontSm,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              // Cho phép xác nhận cả khi chưa chọn để bỏ voucher đã gắn.
              onPressed: _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                elevation: 0,
              ),
              child: Text(
                hasSelection ? 'Thêm' : 'Xong',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppSizes.fontMd,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: AppSizes.sm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSizes.md),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CouponPickerRow extends StatelessWidget {
  final CouponModel coupon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CouponPickerRow({
    required this.coupon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: AppDurations.fast,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.white,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.divider,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: AppSizes.sm),
            Container(
              width: 44,
              height: 44,
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
                      Flexible(
                        child: Text(
                          coupon.discountLabel,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.secondary,
                            fontSize: AppSizes.fontSm,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSizes.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
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
