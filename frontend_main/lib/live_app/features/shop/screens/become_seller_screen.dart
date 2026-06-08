import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/shop/providers/shop_provider.dart';

const _tag = 'BecomeSellerScreen';

/// Flow 3 bước để buyer trở thành seller:
///   Bước 0 – Giới thiệu lợi ích
///   Bước 1 – Điền thông tin shop
///   Bước 2 – Thành công
class BecomeSellerScreen extends StatefulWidget {
  const BecomeSellerScreen({super.key});

  @override
  State<BecomeSellerScreen> createState() => _BecomeSellerScreenState();
}

class _BecomeSellerScreenState extends State<BecomeSellerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int _step = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final shopProvider = context.read<ShopProvider>();
    final ok = await shopProvider.createShop(
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      AppLogger.logUserEvent(action: 'become_seller_success', context: _tag);
      setState(() => _step = 2);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(shopProvider.error ?? 'Có lỗi xảy ra'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Đăng ký bán hàng'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AnimatedSwitcher(
        duration: AppDurations.normal,
        child: switch (_step) {
          0 => _buildIntro(),
          1 => _buildForm(),
          _ => _buildSuccess(),
        },
      ),
    );
  }

  // ── Bước 0: Giới thiệu ────────────────────────────────────────────────────

  Widget _buildIntro() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storefront, size: 52, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          const Text(
            'Bắt đầu bán hàng\ncùng Tropia',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppSizes.fontTitle,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const Text(
            'Tạo cửa hàng và tiếp cận hàng ngàn khách hàng\nqua tính năng Live & Video',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppSizes.fontMd,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSizes.xxl),
          _BenefitRow(
            icon: Icons.live_tv,
            title: 'Livestream bán hàng',
            desc: 'Tương tác trực tiếp với khách hàng',
          ),
          const SizedBox(height: AppSizes.md),
          _BenefitRow(
            icon: Icons.inventory_2_outlined,
            title: 'Quản lý sản phẩm',
            desc: 'Thêm, sửa, xóa sản phẩm dễ dàng',
          ),
          const SizedBox(height: AppSizes.md),
          _BenefitRow(
            icon: Icons.bar_chart,
            title: 'Theo dõi đơn hàng',
            desc: 'Xem doanh thu và thống kê bán hàng',
          ),
          const SizedBox(height: AppSizes.xxl),
          FilledButton(
            onPressed: () => setState(() => _step = 1),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
            ),
            child: const Text(
              'Tạo cửa hàng ngay',
              style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bước 1: Form tạo shop ─────────────────────────────────────────────────

  Widget _buildForm() {
    return Consumer<ShopProvider>(
      key: const ValueKey(1),
      builder: (context, shop, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSizes.md),
                const Text(
                  'Thông tin cửa hàng',
                  style: TextStyle(
                    fontSize: AppSizes.fontXl,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSizes.xs),
                const Text(
                  'Có thể thay đổi sau trong phần quản lý cửa hàng',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: AppSizes.fontSm),
                ),
                const SizedBox(height: AppSizes.xl),
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.divider, width: 2),
                        ),
                        child: const Icon(Icons.storefront, size: 40, color: AppColors.primary),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt, size: 13, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.xl),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Tên cửa hàng *',
                    hintText: 'VD: Tropia Fresh Market',
                    prefixIcon: const Icon(Icons.store_outlined, color: AppColors.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 3) return 'Tối thiểu 3 ký tự';
                    if (v.trim().length > 50) return 'Tối đa 50 ký tự';
                    return null;
                  },
                ),
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: 'Mô tả cửa hàng',
                    hintText: 'Giới thiệu ngắn về cửa hàng của bạn...',
                    alignLabelWithHint: true,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.description_outlined, color: AppColors.textSecondary),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                ),
                const SizedBox(height: AppSizes.xl),
                FilledButton(
                  onPressed: shop.isSaving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                  ),
                  child: shop.isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Tạo cửa hàng',
                          style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(height: AppSizes.md),
                TextButton(
                  onPressed: () => setState(() => _step = 0),
                  child: const Text('Quay lại', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Bước 2: Thành công ────────────────────────────────────────────────────

  Widget _buildSuccess() {
    return Consumer<ShopProvider>(
      key: const ValueKey(2),
      builder: (context, shop, _) {
        return Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, size: 64, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              const Text(
                'Cửa hàng đã được tạo!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppSizes.fontXxl,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                shop.myShop?.name ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppSizes.fontLg,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSizes.md),
              const Text(
                'Bây giờ bạn có thể thêm sản phẩm\nvà bắt đầu bán hàng qua Live!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppSizes.fontMd,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: AppSizes.xxl),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                ),
                child: const Text(
                  'Đến trang quản lý',
                  style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _BenefitRow({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: AppColors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: AppSizes.fontMd,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: AppSizes.fontSm,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
