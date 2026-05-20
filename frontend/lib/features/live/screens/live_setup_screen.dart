// =============================================================================
// live_setup_screen.dart – Shopee-style 2-step live setup
// =============================================================================
// Step 1: Camera preview + title + category + products → "TIẾP THEO"
// Step 2: Review panel with toolbar grid → "Bắt đầu Livestream"
// =============================================================================

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';
import 'package:tropia/features/live/screens/live_host_screen.dart';
import 'package:tropia/features/live/screens/seller_product_picker_screen.dart';

const _tag = 'LiveSetupScreen';

class LiveSetupScreen extends StatefulWidget {
  const LiveSetupScreen({super.key});

  @override
  State<LiveSetupScreen> createState() => _LiveSetupScreenState();
}

class _LiveSetupScreenState extends State<LiveSetupScreen>
    with WidgetsBindingObserver {
  final _titleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  String _selectedCategory = 'Thực phẩm';
  final List<LiveProduct> _selectedProducts = [];
  final List<_LiveCoupon> _coupons = [];
  int _step = 1; // 1 = setup form, 2 = confirm/start

  // ─── Camera ──────────────────────────────────────────────────────────────────
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  int _cameraIndex = 0;
  bool _isCameraOn = true;
  bool _isMicOn = true;
  bool _cameraReady = false;
  String? _cameraError;

  static const _categories = [
    'Thực phẩm', 'Mẹ & Bé', 'Thời trang', 'Giày dép',
    'Mỹ phẩm', 'Đồ uống', 'Hạt khô', 'Rau củ quả',
  ];

  // Toolbar items for step 2
  static const _toolbarItems = [
    (Icons.shopping_bag_outlined, 'Giỏ hàng'),
    (Icons.card_giftcard_outlined, 'Thưởng Xu'),
    (Icons.campaign_outlined, 'Quảng cáo'),
    (Icons.camera_alt_outlined, 'Camera'),
    (Icons.blur_on_outlined, 'Phòng xanh'),
    (Icons.face_retouching_natural, 'Làm đẹp'),
    (Icons.auto_awesome_outlined, 'Hiệu ứng'),
    (Icons.visibility_outlined, 'Xem thẫm'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() => _cameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null) _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _cameraError = 'Không tìm thấy camera');
        return;
      }
      _cameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _startCamera(_cameraIndex);
    } catch (e) {
      AppLogger.logError(_tag, 'Camera init failed', e, null);
      setState(() => _cameraError = 'Không thể khởi động camera: $e');
    }
  }

  Future<void> _startCamera(int index) async {
    final old = _cameraController;
    if (old != null) {
      await old.dispose();
      _cameraController = null;
    }
    final ctrl = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: _isMicOn,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _cameraController = ctrl;
    try {
      await ctrl.initialize();
      if (mounted) setState(() { _cameraReady = true; _cameraError = null; });
    } on CameraException catch (e) {
      AppLogger.logError(_tag, 'Camera start failed', e, null);
      setState(() {
        _cameraReady = false;
        _cameraError = e.description ?? 'Lỗi camera';
      });
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _cameraReady = false);
    await _startCamera(_cameraIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _scrollCtrl.dispose();
    final ctrl = _cameraController;
    _cameraController = null;
    ctrl?.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Full-screen camera preview as background
            Positioned.fill(child: _buildCameraBackground()),
            // Step overlay
            _step == 1 ? _buildStep1Overlay() : _buildStep2Overlay(),
          ],
        ),
      ),
    );
  }

  // ─── Camera background ────────────────────────────────────────────────────────

  Widget _buildCameraBackground() {
    if (_cameraError != null) return _buildCameraErrorBg();
    if (!_cameraReady) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white38)),
      );
    }
    if (!_isCameraOn) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: Icon(Icons.videocam_off, color: Colors.white24, size: 56)),
      );
    }
    return CameraPreview(_cameraController!);
  }

  Widget _buildCameraErrorBg() {
    return Container(
      color: const Color(0xFF111111),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white38, size: 48),
            const SizedBox(height: AppSizes.sm),
            Text(
              _cameraError ?? 'Lỗi camera',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: AppSizes.fontSm),
            ),
            const SizedBox(height: AppSizes.md),
            TextButton(
              onPressed: _initCamera,
              child: const Text('Thử lại', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 1: Form overlay ─────────────────────────────────────────────────────

  Widget _buildStep1Overlay() {
    return Column(
      children: [
        // Top bar
        _buildTopBar(),

        // Middle: preview badge + "Bạn" label float freely
        Expanded(
          child: Stack(
            children: [
              // PREVIEW badge top-left
              Positioned(
                top: AppSizes.md,
                left: AppSizes.md,
                child: _buildPreviewBadge(),
              ),
              // "Bạn" label bottom-left
              Positioned(
                bottom: AppSizes.md,
                left: AppSizes.md,
                child: _buildUserLabel(),
              ),
              // Camera controls bottom-right
              Positioned(
                bottom: AppSizes.md,
                right: AppSizes.md,
                child: _buildCameraControlsVertical(),
              ),
            ],
          ),
        ),

        // Bottom panel (form)
        _buildStep1BottomPanel(),
      ],
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.liveRed.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: Colors.white, size: 8),
          SizedBox(width: 4),
          Text('PREVIEW',
            style: TextStyle(color: Colors.white, fontSize: AppSizes.fontXs, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildUserLabel() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.primary,
          child: Icon(Icons.person, color: Colors.white, size: 16),
        ),
        const SizedBox(width: AppSizes.xs),
        Text('Bạn',
          style: TextStyle(
            color: Colors.white,
            fontSize: AppSizes.fontSm,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 4, color: Colors.black.withValues(alpha: 0.6))],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraControlsVertical() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mic toggle — vị trí người dùng yêu cầu: cùng cột với camera controls
        _CameraIconBtn(
          icon: _isMicOn ? Icons.mic : Icons.mic_off,
          active: _isMicOn,
          activeColor: _isMicOn ? Colors.white : Colors.redAccent,
          onTap: () => setState(() => _isMicOn = !_isMicOn),
        ),
        const SizedBox(height: AppSizes.sm),
        _CameraIconBtn(
          icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
          active: _isCameraOn,
          onTap: () => setState(() => _isCameraOn = !_isCameraOn),
        ),
        const SizedBox(height: AppSizes.sm),
        _CameraIconBtn(
          icon: Icons.flip_camera_android,
          active: _cameras.length > 1,
          onTap: _cameras.length > 1 ? _flipCamera : null,
        ),
      ],
    );
  }

  Widget _buildStep1BottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSizes.sm),

            // Scrollable content
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.of(context).size.height * 0.45 -
                        MediaQuery.of(context).viewInsets.bottom)
                    .clamp(100.0, double.infinity),
              ),
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title field
                    TextFormField(
                      controller: _titleController,
                      maxLength: 60,
                      decoration: InputDecoration(
                        hintText: 'Nhập tiêu đề buổi live...',
                        hintStyle: const TextStyle(color: AppColors.textHint),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                        counterStyle: const TextStyle(color: AppColors.textHint, fontSize: 10),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.md, vertical: AppSizes.sm),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Vui lòng nhập tiêu đề';
                        if (v.trim().length < 5) return 'Tiêu đề phải có ít nhất 5 ký tự';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSizes.sm),

                    // Category dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: AppSizes.fontMd),
                          items: _categories
                              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) { if (v != null) setState(() => _selectedCategory = v); },
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),

                    // Products section
                    _buildProductsSection(),
                    const SizedBox(height: AppSizes.sm),

                    // Coupon section
                    _buildCouponSection(),
                    const SizedBox(height: AppSizes.md),
                  ],
                ),
              ),
            ),

            // TIẾP THEO button
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.md, AppSizes.xs, AppSizes.md,
                AppSizes.md + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _goToStep2,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'TIẾP THEO',
                    style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w800, letterSpacing: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 2: Confirm/start overlay ───────────────────────────────────────────

  Widget _buildStep2Overlay() {
    return Column(
      children: [
        // Top bar with back
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                  onPressed: () => setState(() => _step = 1),
                ),
              ],
            ),
          ),
        ),

        // Middle free space
        Expanded(
          child: Stack(
            children: [
              Positioned(
                top: AppSizes.md,
                left: AppSizes.md,
                child: _buildPreviewBadge(),
              ),
              Positioned(
                bottom: AppSizes.md,
                left: AppSizes.md,
                child: _buildUserLabel(),
              ),
              // Product "Hiển thị" card top-left (like Shopee host view)
              if (_selectedProducts.isNotEmpty)
                Positioned(
                  top: 48,
                  left: AppSizes.md,
                  child: _buildProductDisplayCard(_selectedProducts.first),
                ),
            ],
          ),
        ),

        // Bottom panel
        _buildStep2BottomPanel(),
      ],
    );
  }

  Widget _buildProductImg(String url, double size) {
    final isLocal = !url.startsWith('http');
    if (isLocal) {
      return Image.file(
        File(url), width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size, color: AppColors.surfaceVariant,
          child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textHint),
        ),
      );
    }
    return Image.network(
      url, width: size, height: size, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size, height: size, color: AppColors.surfaceVariant,
        child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textHint),
      ),
    );
  }

  Widget _buildProductDisplayCard(LiveProduct product) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _buildProductImg(product.imageUrl, 36),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.liveRed,
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  ),
                  child: const Text('Hiển thị',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2BottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSizes.md),

          // Toolbar grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            child: GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSizes.sm,
              crossAxisSpacing: AppSizes.xs,
              childAspectRatio: 1.1,
              children: _toolbarItems
                  .map((item) => _buildToolbarItem(item.$1, item.$2))
                  .toList(),
            ),
          ),

          const SizedBox(height: AppSizes.md),
          const Divider(height: 1),

          // Bottom action row
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSizes.md, AppSizes.sm, AppSizes.md,
              AppSizes.sm + MediaQuery.of(context).padding.bottom,
            ),
            child: Row(
              children: [
                // Quay lại button
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _step = 1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Quay lại',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppSizes.fontMd)),
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                // Bắt đầu Livestream button
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _startLive,
                    icon: const Icon(Icons.live_tv, size: 18),
                    label: const Text('Bắt đầu Livestream',
                      style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.liveRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildToolbarItem(IconData icon, String label) {
    return GestureDetector(
      onTap: () => AppLogger.logUserEvent(
        action: 'toolbar_tapped',
        context: _tag,
        metadata: {'item': label},
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42, height: 42,
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Products section ─────────────────────────────────────────────────────────

  Widget _buildProductsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product list (Shopee-style: image with overlay)
        if (_selectedProducts.isNotEmpty) ...[
          ...(_selectedProducts.asMap().entries.map((e) => _ProductSetupTile(
            product: e.value,
            index: e.key,
            onRemove: () => setState(() => _selectedProducts.removeAt(e.key)),
          ))),
          const SizedBox(height: AppSizes.xs),
        ],

        // "Thêm sản phẩm liên quan" button
        GestureDetector(
          onTap: _showAddProductSheet,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSizes.sm + 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: AppColors.primary, size: 18),
                SizedBox(width: 6),
                Text(
                  'Thêm sản phẩm liên quan',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: AppSizes.fontSm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Coupon section ───────────────────────────────────────────────────────────

  Widget _buildCouponSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Coupon chips list
        if (_coupons.isNotEmpty) ...[
          Wrap(
            spacing: AppSizes.xs,
            runSpacing: AppSizes.xs,
            children: _coupons.asMap().entries.map((e) {
              final c = e.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_offer, size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      c.label,
                      style: const TextStyle(
                        fontSize: AppSizes.fontXs,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setState(() => _coupons.removeAt(e.key)),
                      child: const Icon(Icons.close, size: 12, color: AppColors.primary),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSizes.xs),
        ],

        // "Thêm coupon" button
        GestureDetector(
          onTap: _showAddCouponDialog,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSizes.sm + 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_offer_outlined, color: AppColors.secondary, size: 18),
                SizedBox(width: 6),
                Text(
                  'Thêm coupon cho buổi live',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w600,
                    fontSize: AppSizes.fontSm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddCouponDialog() async {
    if (_coupons.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tối đa 5 coupon mỗi buổi live')),
      );
      return;
    }
    final coupon = await showDialog<_LiveCoupon>(
      context: context,
      builder: (_) => const _CouponDialog(),
    );
    if (coupon != null && mounted) {
      setState(() => _coupons.add(coupon));
    }
  }

  Future<void> _showAddProductSheet() async {
    final result = await Navigator.push<List<LiveProduct>>(
      context,
      MaterialPageRoute(
        builder: (_) => SellerProductPickerScreen(
          alreadySelected: List.from(_selectedProducts),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedProducts..clear()..addAll(result);
      });
    }
  }

  // ─── Navigation ───────────────────────────────────────────────────────────────

  void _goToStep2() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = 2);
    AppLogger.logUserEvent(
      action: 'live_setup_step2',
      context: _tag,
      metadata: {
        'title': _titleController.text.trim(),
        'category': _selectedCategory,
        'productCount': _selectedProducts.length,
      },
    );
  }

  Future<void> _startLive() async {
    final title = _titleController.text.trim();

    AppLogger.logUserEvent(
      action: 'host_live_started',
      context: _tag,
      metadata: {
        'title': title,
        'category': _selectedCategory,
        'productCount': _selectedProducts.length,
      },
    );

    final ctrl = _cameraController;
    _cameraController = null;
    if (mounted) setState(() => _cameraReady = false);
    await ctrl?.dispose();
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LiveHostScreen(
          title: title,
          category: _selectedCategory,
          products: List.from(_selectedProducts),
          thumbnailUrl: null,
          coupons: _coupons.map((c) => c.toMap()).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _LiveCoupon {
  final String code;
  final double discountValue;
  final bool isPercentage;
  final double minOrderValue;
  final int? maxUses;
  final DateTime expiresAt;

  const _LiveCoupon({
    required this.code,
    required this.discountValue,
    required this.isPercentage,
    required this.minOrderValue,
    required this.expiresAt,
    this.maxUses,
  });

  String get label {
    final discount = isPercentage
        ? '${discountValue.toInt()}%'
        : '${_fmt(discountValue)}đ';
    final limitSuffix = maxUses != null ? ' ×$maxUses' : '';
    return 'Giảm $discount$limitSuffix';
  }

  String toCode() => code;

  Map<String, dynamic> toMap() => {
    'code':          code,
    'discountValue': discountValue,
    'isPercentage':  isPercentage,
    'minOrderValue': minOrderValue,
    'expiresAt':     expiresAt.toUtc().toIso8601String(),
    if (maxUses != null) 'maxUses': maxUses,
  };

  static String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}tr';
    if (v >= 1000) return '${(v / 1000).toInt()}K';
    return v.toInt().toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coupon creation dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CouponDialog extends StatefulWidget {
  const _CouponDialog();

  @override
  State<_CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends State<_CouponDialog> {
  final _codeCtrl     = TextEditingController();
  final _valueCtrl    = TextEditingController();
  final _minOrderCtrl = TextEditingController();
  final _maxUsesCtrl  = TextEditingController();
  final _formKey      = GlobalKey<FormState>();
  bool _isPercentage  = false;
  DateTime? _expiresAt;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _minOrderCtrl.dispose();
    _maxUsesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expiresAt ?? date.add(const Duration(hours: 23, minutes: 59))),
    );
    if (!mounted) return;
    setState(() {
      _expiresAt = time == null
          ? date.copyWith(hour: 23, minute: 59)
          : date.copyWith(hour: time.hour, minute: time.minute);
    });
  }

  String _fmtExpiry(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
    final t = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    return '$d $t';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_expiresAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ngày hết hạn')),
      );
      return;
    }
    final value    = double.tryParse(_valueCtrl.text.trim()) ?? 0;
    final minOrder = double.tryParse(_minOrderCtrl.text.trim()) ?? 0;
    final maxUses  = int.tryParse(_maxUsesCtrl.text.trim());
    if (_isPercentage && (value <= 0 || value > 100)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giảm % phải từ 1–100')),
      );
      return;
    }
    Navigator.pop(
      context,
      _LiveCoupon(
        code:          _codeCtrl.text.trim().toUpperCase(),
        discountValue: value,
        isPercentage:  _isPercentage,
        minOrderValue: minOrder,
        maxUses:       maxUses,
        expiresAt:     _expiresAt!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tạo coupon live', style: TextStyle(fontWeight: FontWeight.w700)),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coupon code
              TextFormField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Mã coupon (VD: LIVE20K)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Vui lòng nhập mã';
                  if (v.trim().length < 3) return 'Tối thiểu 3 ký tự';
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.sm),

              // Discount type toggle
              Row(
                children: [
                  const Text('Loại giảm:', style: TextStyle(fontSize: AppSizes.fontSm)),
                  const SizedBox(width: AppSizes.sm),
                  _TypeChip(
                    label: 'VNĐ',
                    selected: !_isPercentage,
                    onTap: () => setState(() => _isPercentage = false),
                  ),
                  const SizedBox(width: AppSizes.xs),
                  _TypeChip(
                    label: '%',
                    selected: _isPercentage,
                    onTap: () => setState(() => _isPercentage = true),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),

              // Discount value
              TextFormField(
                controller: _valueCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _isPercentage ? 'Giá trị giảm (%)' : 'Giá trị giảm (VNĐ)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixText: _isPercentage ? '%' : 'đ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nhập giá trị giảm';
                  if (double.tryParse(v.trim()) == null) return 'Số không hợp lệ';
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.sm),

              // Min order
              TextFormField(
                controller: _minOrderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Đơn tối thiểu (VNĐ, để trống = không giới hạn)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixText: 'đ',
                ),
              ),
              const SizedBox(height: AppSizes.sm),

              // Max uses
              TextFormField(
                controller: _maxUsesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số lượt dùng tối đa (để trống = không giới hạn)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixText: 'lượt',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Phải là số nguyên dương';
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.sm),

              // Expires at
              GestureDetector(
                onTap: _pickExpiry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: _expiresAt == null ? AppColors.error : AppColors.divider),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 16,
                          color: _expiresAt == null ? AppColors.error : AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        _expiresAt == null ? 'Ngày hết hạn *' : _fmtExpiry(_expiresAt!),
                        style: TextStyle(
                          fontSize: AppSizes.fontSm,
                          color: _expiresAt == null ? AppColors.error : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Tạo coupon'),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.secondary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
          border: Border.all(color: selected ? AppColors.secondary : AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppSizes.fontXs,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CameraIconBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;
  final Color? activeColor;

  const _CameraIconBtn({
    required this.icon,
    required this.active,
    this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: active ? (activeColor ?? Colors.white) : Colors.white38,
          size: 20,
        ),
      ),
    );
  }
}

// Shopee-style product tile: thumbnail with name+description overlay, delete + drag icons
class _ProductSetupTile extends StatelessWidget {
  final LiveProduct product;
  final int index;
  final VoidCallback onRemove;

  const _ProductSetupTile({
    required this.product,
    required this.index,
    required this.onRemove,
  });

  Widget _buildProductImg(String url, double size) {
    final isLocal = !url.startsWith('http');
    if (isLocal) {
      return Image.file(
        File(url), width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size, color: AppColors.surfaceVariant,
          child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textHint),
        ),
      );
    }
    return Image.network(
      url, width: size, height: size, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size, height: size, color: AppColors.surfaceVariant,
        child: const Icon(Icons.image_outlined, size: 18, color: AppColors.textHint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.xs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Thumbnail with name overlay
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppSizes.radiusMd)),
            child: Stack(
              children: [
                _buildProductImg(product.imageUrl, 72),
                // Dark gradient overlay
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                  ),
                ),
                // Product name on top of image
                Positioned(
                  bottom: 4, left: 4, right: 4,
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppSizes.sm),

          // Price info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppSizes.fontSm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtPrice(product.salePrice),
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: AppSizes.fontXs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Actions: delete + reorder
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.drag_handle, color: AppColors.textHint, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtPrice(double price) {
    if (price >= 1000000) return '${(price / 1000000).toStringAsFixed(1)}tr đ';
    if (price >= 1000) return '${(price / 1000).toInt()}K đ';
    return '${price.toInt()}đ';
  }
}
