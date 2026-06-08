// =============================================================================
// flash_sale_admin_screen.dart
// =============================================================================
// Admin: tạo / quản lý Flash Sale (Shopee "Flash Sale").
//   - [FlashSaleAdminScreen]: danh sách đợt (bật/tắt, xoá, vào sửa)
//   - [FlashSaleEditScreen]:  tạo mới / sửa (tên, khung giờ, sản phẩm + giá flash)
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/flashsale/data/flash_sale_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/flashsale/models/flash_sale_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/product/data/product_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/product/models/product_model.dart';

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

String _fmtDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// List screen
// ─────────────────────────────────────────────────────────────────────────────

class FlashSaleAdminScreen extends StatefulWidget {
  const FlashSaleAdminScreen({super.key});

  @override
  State<FlashSaleAdminScreen> createState() => _FlashSaleAdminScreenState();
}

class _FlashSaleAdminScreenState extends State<FlashSaleAdminScreen> {
  final _repo = FlashSaleRepository.instance;
  List<FlashSale> _sales = [];
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
      final list = await _repo.listAll();
      if (mounted) setState(() => _sales = list);
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FlashSaleEditScreen()),
    );
    if (changed == true) _load();
  }

  Future<void> _edit(FlashSale sale) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FlashSaleEditScreen(sale: sale)),
    );
    if (changed == true) _load();
  }

  Future<void> _toggleActive(FlashSale sale, bool active) async {
    try {
      await _repo.update(sale.id, isActive: active);
      _load();
    } catch (e) {
      _snack(AuthService.errorMessage(e));
    }
  }

  Future<void> _delete(FlashSale sale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá flash sale?'),
        content: Text('Xoá đợt "${sale.name}" và toàn bộ sản phẩm trong đợt?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(sale.id);
      _load();
    } catch (e) {
      _snack(AuthService.errorMessage(e));
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flash Sale'),
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tạo đợt'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.secondary),
              )
            : _error != null
            ? _ErrorView(message: _error!, onRetry: _load)
            : _sales.isEmpty
            ? _EmptyView(onCreate: _create)
            : ListView.separated(
                padding: const EdgeInsets.all(AppSizes.md),
                itemCount: _sales.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSizes.sm),
                itemBuilder: (_, i) => _SaleCard(
                  sale: _sales[i],
                  onTap: () => _edit(_sales[i]),
                  onToggle: (v) => _toggleActive(_sales[i], v),
                  onDelete: () => _delete(_sales[i]),
                ),
              ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final FlashSale sale;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _SaleCard({
    required this.sale,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = sale.isLive
        ? ('Đang chạy', AppColors.success)
        : sale.isUpcoming
        ? ('Sắp diễn ra', AppColors.warning)
        : sale.isActive
        ? ('Đã kết thúc', AppColors.textHint)
        : ('Đã tắt', AppColors.textHint);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sale.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppSizes.fontMd,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: AppSizes.fontXs,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_fmtDateTime(sale.startsAt)} → ${_fmtDateTime(sale.endsAt)}  •  ${sale.products.length} sản phẩm',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppSizes.fontXs,
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              Row(
                children: [
                  Switch(
                    value: sale.isActive,
                    activeThumbColor: AppColors.secondary,
                    onChanged: onToggle,
                  ),
                  Text(
                    sale.isActive ? 'Bật' : 'Tắt',
                    style: const TextStyle(
                      fontSize: AppSizes.fontXs,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                    ),
                    tooltip: 'Xoá',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create / Edit screen
// ─────────────────────────────────────────────────────────────────────────────

/// 1 dòng sản phẩm đang soạn trong đợt flash sale.
class _EditProduct {
  final String productId;
  final String name;
  final String? image;
  final int basePrice;
  int flashPrice;
  int? stockLimit;
  _EditProduct({
    required this.productId,
    required this.name,
    this.image,
    required this.basePrice,
    required this.flashPrice,
    this.stockLimit,
  });
}

class FlashSaleEditScreen extends StatefulWidget {
  final FlashSale? sale;
  const FlashSaleEditScreen({super.key, this.sale});

  @override
  State<FlashSaleEditScreen> createState() => _FlashSaleEditScreenState();
}

class _FlashSaleEditScreenState extends State<FlashSaleEditScreen> {
  final _repo = FlashSaleRepository.instance;
  final _nameCtrl = TextEditingController();
  late DateTime _startsAt;
  late DateTime _endsAt;
  final List<_EditProduct> _products = [];
  bool _saving = false;

  bool get _isEdit => widget.sale != null;

  @override
  void initState() {
    super.initState();
    final s = widget.sale;
    final now = DateTime.now();
    _nameCtrl.text = s?.name ?? '';
    _startsAt = s?.startsAt ?? now.add(const Duration(minutes: 5));
    _endsAt = s?.endsAt ?? now.add(const Duration(hours: 2));
    if (s != null) {
      for (final p in s.products) {
        _products.add(
          _EditProduct(
            productId: p.productId,
            name: p.name,
            image: p.image,
            basePrice: p.basePrice,
            flashPrice: p.flashPrice,
            stockLimit: p.stockLimit,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final base = isStart ? _startsAt : _endsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;
    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _startsAt = dt;
        if (!_endsAt.isAfter(_startsAt))
          _endsAt = _startsAt.add(const Duration(hours: 1));
      } else {
        _endsAt = dt;
      }
    });
  }

  Future<void> _addProduct() async {
    final product = await showModalBottomSheet<ProductModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusLg),
        ),
      ),
      builder: (_) => const _ProductPickerSheet(),
    );
    if (product == null || !mounted) return;
    if (_products.any((p) => p.productId == product.id)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sản phẩm đã có trong đợt')));
      return;
    }
    setState(() {
      _products.add(
        _EditProduct(
          productId: product.id,
          name: product.name,
          image: null,
          basePrice: product.basePrice,
          flashPrice: product.basePrice,
        ),
      );
    });
  }

  Future<void> _editFlashPrice(_EditProduct p) async {
    final priceCtrl = TextEditingController(text: p.flashPrice.toString());
    final stockCtrl = TextEditingController(
      text: p.stockLimit?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Giá gốc: ${_fmtVnd(p.basePrice)}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSizes.sm),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Giá flash (đ)',
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            TextField(
              controller: stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Giới hạn số lượng (để trống = không giới hạn)',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final price = int.tryParse(priceCtrl.text.trim());
    final stock = stockCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(stockCtrl.text.trim());
    if (price == null || price < 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Giá flash không hợp lệ')));
      }
      return;
    }
    setState(() {
      p.flashPrice = price;
      p.stockLimit = stock;
    });
  }

  List<FlashSaleProductInput> get _inputs => _products
      .map(
        (p) => FlashSaleProductInput(
          productId: p.productId,
          flashPrice: p.flashPrice,
          stockLimit: p.stockLimit,
        ),
      )
      .toList();

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nhập tên đợt flash sale')));
      return;
    }
    if (!_endsAt.isAfter(_startsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thời gian kết thúc phải sau thời gian bắt đầu'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _repo.update(
          widget.sale!.id,
          name: name,
          startsAt: _startsAt,
          endsAt: _endsAt,
        );
        await _repo.setProducts(widget.sale!.id, _inputs);
      } else {
        await _repo.create(
          name: name,
          startsAt: _startsAt,
          endsAt: _endsAt,
          products: _inputs,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AuthService.errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Sửa Flash Sale' : 'Tạo Flash Sale'),
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.md),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Tên đợt',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'Bắt đầu',
                  value: _startsAt,
                  onTap: () => _pickDateTime(isStart: true),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _DateField(
                  label: 'Kết thúc',
                  value: _endsAt,
                  onTap: () => _pickDateTime(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          Row(
            children: [
              const Text(
                'Sản phẩm',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppSizes.fontMd,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addProduct,
                icon: const Icon(Icons.add, color: AppColors.secondary),
                label: const Text(
                  'Thêm',
                  style: TextStyle(color: AppColors.secondary),
                ),
              ),
            ],
          ),
          if (_products.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSizes.lg),
              child: Center(
                child: Text(
                  'Chưa có sản phẩm — bấm "Thêm" để chọn',
                  style: TextStyle(color: AppColors.textHint),
                ),
              ),
            )
          else
            ..._products.map(
              (p) => _ProductRow(
                product: p,
                onEdit: () => _editFlashPrice(p),
                onRemove: () => setState(() => _products.remove(p)),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
      bottomSheet: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSizes.md,
          AppSizes.sm,
          AppSizes.md,
          AppSizes.sm + MediaQuery.of(context).padding.bottom,
        ),
        child: SizedBox(
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
                : Text(
                    _isEdit ? 'Lưu thay đổi' : 'Tạo đợt',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(_fmtDateTime(value)),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final _EditProduct product;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  const _ProductRow({
    required this.product,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: SizedBox(
          width: 44,
          height: 44,
          child: product.image != null
              ? CachedNetworkImage(imageUrl: product.image!, fit: BoxFit.cover)
              : Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.image_outlined,
                    color: AppColors.textHint,
                  ),
                ),
        ),
      ),
      title: Text(
        product.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: AppSizes.fontSm),
      ),
      subtitle: Text(
        '${_fmtVnd(product.flashPrice)}  •  gốc ${_fmtVnd(product.basePrice)}'
        '${product.stockLimit != null ? '  •  SL ${product.stockLimit}' : ''}',
        style: const TextStyle(fontSize: AppSizes.fontXs),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit, size: 20, color: AppColors.secondary),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 20, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product picker (search catalog)
// ─────────────────────────────────────────────────────────────────────────────

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _ctrl = TextEditingController();
  List<ProductModel> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final res = await ProductRepository.instance.browse(
        search: q.isEmpty ? null : q,
        limit: 30,
      );
      if (mounted) setState(() => _results = res.items);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Tìm sản phẩm...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.secondary,
                      ),
                    )
                  : _results.isEmpty
                  ? const Center(
                      child: Text(
                        'Không có sản phẩm',
                        style: TextStyle(color: AppColors.textHint),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _results[i];
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusSm,
                            ),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: p.thumbnail != null
                                  ? CachedNetworkImage(
                                      imageUrl: p.thumbnail!,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: AppColors.surfaceVariant,
                                      child: const Icon(
                                        Icons.image_outlined,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                            ),
                          ),
                          title: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: AppSizes.fontSm),
                          ),
                          subtitle: Text(
                            _fmtVnd(p.basePrice),
                            style: const TextStyle(
                              fontSize: AppSizes.fontXs,
                              color: AppColors.secondary,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyView({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.bolt, size: 64, color: AppColors.textHint),
        const SizedBox(height: AppSizes.sm),
        const Center(
          child: Text(
            'Chưa có đợt flash sale nào',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Center(
          child: FilledButton.icon(
            onPressed: onCreate,
            style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
            icon: const Icon(Icons.add),
            label: const Text('Tạo đợt đầu tiên'),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.error_outline, size: 56, color: AppColors.textHint),
        const SizedBox(height: AppSizes.sm),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ),
      ],
    );
  }
}
