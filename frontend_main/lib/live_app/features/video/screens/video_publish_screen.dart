// =============================================================================
// video_publish_screen.dart
// =============================================================================
// Màn "Thêm mô tả": preview + caption (hashtag tô màu inline + gợi ý #) +
// chọn ảnh bìa + toggle → nút Đăng (upload MP4 + tạo bản ghi).
//
// Hashtag kiểu TikTok/Shopee: gõ "#tu" trong ô mô tả sẽ hiện dropdown gợi ý
// (lấy từ GET /api/videos/hashtags), chạm để chèn; mọi #hashtag trong mô tả
// được tô xanh và được tách ra gửi kèm khi đăng.
//
// Tự gọi VideoRepository (không qua VideoProvider) vì được push ngoài provider
// scope; trả VideoPost qua Navigator.pop khi thành công.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/coupon/data/coupon_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/coupon/screens/seller_coupon_picker_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/models/live_stream_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/screens/seller_product_picker_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/data/video_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';

/// Màu hashtag (xanh dương dịu, giống chữ "#ngockem" trong UI tham chiếu).
const Color _kHashtagColor = Color(0xFF2B5CB8);

/// 1 token hashtag = dấu '#' + chữ/số/_ (hỗ trợ tiếng Việt qua \p{L}).
final RegExp _kHashtagRegex = RegExp(r'#[\p{L}\p{N}_]+', unicode: true);

/// Ký tự hợp lệ bên trong 1 hashtag (không gồm dấu '#').
final RegExp _kTagCharRegex = RegExp(r'[\p{L}\p{N}_]', unicode: true);

bool _isTagChar(String ch) => _kTagCharRegex.hasMatch(ch);
bool _isBoundary(String ch) => ch.trim().isEmpty; // khoảng trắng / xuống dòng

/// Controller tô màu mọi #hashtag trong text ngay khi gõ (inline highlight).
class _HashtagEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final spans = <InlineSpan>[];
    final t = text;
    var last = 0;
    for (final m in _kHashtagRegex.allMatches(t)) {
      if (m.start > last) {
        spans.add(TextSpan(text: t.substring(last, m.start), style: base));
      }
      spans.add(
        TextSpan(
          text: t.substring(m.start, m.end),
          style: base.copyWith(
            color: _kHashtagColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      last = m.end;
    }
    if (last < t.length) {
      spans.add(TextSpan(text: t.substring(last), style: base));
    }
    return TextSpan(style: base, children: spans);
  }
}

/// Token hashtag đang ở dưới con trỏ: [hashStart] là vị trí dấu '#',
/// [tokenEnd] là cuối token, [query] là phần đã gõ sau '#'.
class _HashtagQuery {
  final int hashStart;
  final int tokenEnd;
  final String query;
  const _HashtagQuery(this.hashStart, this.tokenEnd, this.query);
}

class VideoPublishScreen extends StatefulWidget {
  final XFile video;
  const VideoPublishScreen({super.key, required this.video});

  @override
  State<VideoPublishScreen> createState() => _VideoPublishScreenState();
}

class _VideoPublishScreenState extends State<VideoPublishScreen> {
  final _repo = VideoRepository();
  final _picker = ImagePicker();
  final _caption = _HashtagEditingController();
  final _captionFocus = FocusNode();

  VideoPlayerController? _preview;
  XFile? _cover;
  bool _allowReuse = true;
  bool _saveToDevice = false;
  bool _autoShareFacebook = false;
  bool _publishing = false;
  List<LiveProduct> _products = [];
  List<CouponModel> _coupons = [];

  // Gợi ý hashtag (#) khi con trỏ đang ở trong 1 token hashtag.
  bool _showSuggest = false;
  bool _loadingSuggest = false;
  String? _suggestQuery; // query đang chờ/đã fetch, để khỏi gọi lại trùng
  List<HashtagSuggestion> _suggestions = const [];
  Timer? _suggestDebounce;

  @override
  void initState() {
    super.initState();
    _caption.addListener(_onCaptionChanged);
    _initPreview();
  }

  Future<void> _initPreview() async {
    if (kIsWeb) return; // file:// preview chỉ chạy trên mobile/desktop
    try {
      final ctrl = VideoPlayerController.file(File(widget.video.path));
      _preview = ctrl;
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(0);
      await ctrl.play();
      if (mounted) setState(() {});
    } catch (_) {
      _preview = null;
    }
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _preview?.dispose();
    _caption.removeListener(_onCaptionChanged);
    _caption.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final img = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
    );
    if (img != null && mounted) setState(() => _cover = img);
  }

  /// Bắt 1 frame đầu video làm ảnh bìa khi user không tự chọn cover. Trả về
  /// null nếu chạy trên web (plugin không hỗ trợ) hoặc gặp lỗi — lúc đó video
  /// đăng không kèm thumbnail (giống hành vi cũ), không chặn việc đăng.
  Future<XFile?> _autoThumbnail() async {
    if (kIsWeb) return null;
    try {
      final Uint8List? bytes = await VideoThumbnail.thumbnailData(
        video: widget.video.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 75,
      );
      if (bytes == null || bytes.isEmpty) return null;
      return XFile.fromData(bytes, mimeType: 'image/jpeg', name: 'thumb.jpg');
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickProducts() async {
    final result = await Navigator.of(context).push<List<LiveProduct>>(
      MaterialPageRoute(
        builder: (_) => SellerProductPickerScreen(alreadySelected: _products),
      ),
    );
    if (result != null && mounted) setState(() => _products = result);
  }

  Future<void> _pickCoupons() async {
    final result = await Navigator.of(context).push<List<CouponModel>>(
      MaterialPageRoute(
        builder: (_) => SellerCouponPickerScreen(alreadySelected: _coupons),
      ),
    );
    if (result != null && mounted) setState(() => _coupons = result);
  }

  /// Tách mọi #hashtag từ nội dung mô tả (loại trùng, tối đa 20) để gửi kèm
  /// vào trường hashtags[] của backend — caption vẫn giữ nguyên #tag inline.
  List<String> _parseHashtags() {
    final seen = <String>{};
    for (final m in _kHashtagRegex.allMatches(_caption.text)) {
      final tag = m.group(0)!.substring(1);
      if (tag.isNotEmpty) seen.add(tag);
      if (seen.length >= 20) break;
    }
    return seen.toList();
  }

  /// Xác định token hashtag đang nằm dưới con trỏ (nếu có) để biết khi nào mở
  /// dropdown gợi ý và phần query đang gõ là gì.
  _HashtagQuery? _activeHashtag() {
    final sel = _caption.selection;
    final text = _caption.text;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final cursor = sel.baseOffset;
    if (cursor < 0 || cursor > text.length) return null;

    var start = cursor;
    while (start > 0 && _isTagChar(text[start - 1])) {
      start--;
    }
    // Phải có dấu '#' ngay trước chuỗi chữ, và '#' đứng đầu hoặc sau khoảng trắng.
    if (start == 0 || text[start - 1] != '#') return null;
    final hashStart = start - 1;
    if (hashStart > 0 && !_isBoundary(text[hashStart - 1])) return null;

    var end = cursor;
    while (end < text.length && _isTagChar(text[end])) {
      end++;
    }
    return _HashtagQuery(hashStart, end, text.substring(start, cursor));
  }

  void _onCaptionChanged() {
    final active = _activeHashtag();
    if (active == null) {
      _suggestDebounce?.cancel();
      _suggestQuery = null;
      if (_showSuggest) {
        setState(() {
          _showSuggest = false;
          _loadingSuggest = false;
          _suggestions = const [];
        });
      }
      return;
    }
    final q = active.query;
    if (q == _suggestQuery && _showSuggest) return; // không đổi → bỏ qua
    _suggestQuery = q;
    setState(() {
      _showSuggest = true;
      _loadingSuggest = true;
    });
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _fetchSuggestions(q),
    );
  }

  Future<void> _fetchSuggestions(String q) async {
    final list = await _repo.searchHashtags(q);
    if (!mounted || _suggestQuery != q) return; // query đã đổi trong lúc chờ
    setState(() {
      _suggestions = list;
      _loadingSuggest = false;
    });
  }

  /// Nút "# Hashtag": chèn dấu '#' tại con trỏ (thêm khoảng trắng nếu cần) rồi
  /// focus lại ô mô tả để bàn phím gõ tiếp.
  void _insertHashSign() {
    final sel = _caption.selection;
    final text = _caption.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final needSpace = start > 0 && !_isBoundary(text[start - 1]);
    final insert = needSpace ? ' #' : '#';
    _caption.value = TextEditingValue(
      text: text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    _captionFocus.requestFocus();
  }

  /// Chạm 1 gợi ý → thay token đang gõ bằng "#tag " (kèm khoảng trắng) rồi
  /// đóng dropdown.
  void _applySuggestion(HashtagSuggestion s) {
    final active = _activeHashtag();
    if (active == null) return;
    final replacement = '#${s.tag} ';
    final text = _caption.text;
    _caption.value = TextEditingValue(
      text: text.replaceRange(active.hashStart, active.tokenEnd, replacement),
      selection: TextSelection.collapsed(
        offset: active.hashStart + replacement.length,
      ),
    );
    _suggestQuery = null;
    setState(() {
      _showSuggest = false;
      _loadingSuggest = false;
      _suggestions = const [];
    });
    _captionFocus.requestFocus();
  }

  /// "12345" → "12,3k", "1500000" → "1,5tr" (kiểu số đếm tiếng Việt).
  String _formatCount(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')}tr';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
    }
    return '$n';
  }

  Future<void> _publish() async {
    if (_publishing) return;
    if (!AuthService.instance.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn cần đăng nhập để đăng video')),
      );
      return;
    }
    setState(() => _publishing = true);
    try {
      // User chưa chọn ảnh bìa → tự bắt frame đầu video làm thumbnail, để lưới
      // hồ sơ không hiện hộp đen. Web không hỗ trợ → bỏ qua (cover = null).
      final cover = _cover ?? await _autoThumbnail();
      final uploaded = await _repo.uploadVideo(widget.video, thumbnail: cover);
      final dur = _preview?.value.duration.inSeconds ?? 0;
      final size = _preview?.value.size ?? Size.zero;
      final post = await _repo.createVideo(
        videoUrl: uploaded['video_url']!,
        thumbnailUrl: uploaded['thumbnail_url'],
        caption: _caption.text.trim(),
        hashtags: _parseHashtags(),
        durationSec: dur,
        width: size.width.round(),
        height: size.height.round(),
        allowReuse: _allowReuse,
        productIds: _products
            .map((p) => p.productId ?? p.id)
            .where((id) => id.isNotEmpty)
            .toList(),
        couponIds: _coupons
            .map((c) => c.id)
            .where((id) => id.isNotEmpty)
            .toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đăng video thành công')));
      Navigator.of(context).pop(post);
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AuthService.errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
        title: const Text('Thêm mô tả'),
      ),
      body: AbsorbPointer(
        absorbing: _publishing,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.md),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _caption,
                    focusNode: _captionFocus,
                    maxLines: 4,
                    maxLength: 150,
                    decoration: const InputDecoration(
                      hintText: 'Thêm mô tả cho video của bạn',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                _buildCover(),
              ],
            ),
            const SizedBox(height: AppSizes.xs),
            // Nút chèn '#' — gõ tiếp sẽ hiện gợi ý hashtag ngay bên dưới.
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _insertHashSign,
                icon: const Icon(Icons.tag, size: 16),
                label: const Text('Hashtag'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.divider),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.md,
                    vertical: AppSizes.xs,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            const Divider(),
            // Khi đang gõ trong 1 hashtag → hiện gợi ý thay cho phần tuỳ chọn.
            if (_showSuggest)
              _buildHashtagSuggestions()
            else ...[
              _buildProductSection(),
              const Divider(),
              _buildCouponSection(),
              const Divider(),
              SwitchListTile(
                value: _allowReuse,
                onChanged: (v) => setState(() => _allowReuse = v),
                activeThumbColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
                title: const Text('Cho phép sử dụng lại nội dung'),
                subtitle: const Text(
                  'Duet, Ghép nối, nhãn dán và clip',
                  style: TextStyle(
                    fontSize: AppSizes.fontSm,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              SwitchListTile(
                value: _saveToDevice,
                onChanged: (v) => setState(() => _saveToDevice = v),
                activeThumbColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
                title: const Text('Lưu về máy'),
              ),
              _buildAutoShareSection(),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _publishing ? null : _publish,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
              ),
              child: _publishing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Đăng',
                      style: TextStyle(
                        fontSize: AppSizes.fontLg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Dropdown gợi ý hashtag (hiện khi con trỏ đang ở trong 1 token '#...').
  Widget _buildHashtagSuggestions() {
    if (_loadingSuggest && _suggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSizes.md),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSizes.sm),
            Text(
              'Đang tìm hashtag...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    if (_suggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSizes.md),
        child: Text(
          'Không tìm thấy hashtag phù hợp',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return Column(
      children: [
        for (final s in _suggestions)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            onTap: () => _applySuggestion(s),
            title: Text(
              '#${s.tag}',
              style: const TextStyle(
                color: _kHashtagColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: Text(
              '${_formatCount(s.viewCount)} lượt xem',
              style: const TextStyle(
                fontSize: AppSizes.fontSm,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  /// "Tự động chia sẻ đến" — nhấn vào icon Facebook để bật/tắt tự chia sẻ
  /// sau khi đăng. Icon sáng xanh khi bật, xám khi tắt.
  Widget _buildAutoShareSection() {
    return ListTile(
      onTap: () => setState(() => _autoShareFacebook = !_autoShareFacebook),
      contentPadding: EdgeInsets.zero,
      title: const Text('Tự động chia sẻ đến'),
      trailing: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _autoShareFacebook
                ? const Color(0xFF1877F2)
                : AppColors.divider,
          ),
        ),
        child: Icon(
          Icons.facebook,
          size: 20,
          color: _autoShareFacebook
              ? const Color(0xFF1877F2)
              : AppColors.textHint,
        ),
      ),
    );
  }

  Widget _buildCover() {
    return GestureDetector(
      onTap: _pickCover,
      child: Container(
        width: 100,
        height: 132,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_cover != null)
              Image.file(File(_cover!.path), fit: BoxFit.cover)
            else if (_preview != null && _preview!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _preview!.value.size.width == 0
                      ? 90
                      : _preview!.value.size.width,
                  height: _preview!.value.size.height == 0
                      ? 120
                      : _preview!.value.size.height,
                  child: VideoPlayer(_preview!),
                ),
              )
            else
              const Center(
                child: Icon(Icons.movie_outlined, color: Colors.white38),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: const Text(
                  'Chọn ảnh bìa',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.fontXs,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Liên kết sản phẩm" — mở picker, hiển thị số lượng + dải ảnh đã chọn.
  Widget _buildProductSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          onTap: _pickProducts,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.shopping_bag_outlined,
            color: AppColors.secondary,
          ),
          title: const Text('Liên kết sản phẩm'),
          subtitle: Text(
            _products.isEmpty
                ? 'Thêm sản phẩm để người xem mua ngay trong video'
                : 'Đã chọn ${_products.length} sản phẩm',
            style: const TextStyle(
              fontSize: AppSizes.fontSm,
              color: AppColors.textSecondary,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
        ),
        if (_products.isNotEmpty)
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _products.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSizes.xs),
              itemBuilder: (_, i) => _buildProductChip(_products[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildProductChip(LiveProduct p) {
    final isLocal = !p.imageUrl.startsWith('http');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          child: SizedBox(
            width: 56,
            height: 56,
            child: isLocal
                ? Image.file(
                    File(p.imageUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _chipFallback(),
                  )
                : CachedNetworkImage(
                    imageUrl: p.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _chipFallback(),
                    errorWidget: (_, __, ___) => _chipFallback(),
                  ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => setState(() => _products.remove(p)),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chipFallback() => Container(
    color: AppColors.surfaceVariant,
    child: const Icon(
      Icons.image_outlined,
      color: AppColors.textHint,
      size: 20,
    ),
  );

  /// "Voucher" — mở picker coupon, hiển thị số lượng + dải chip coupon đã chọn
  /// (Shopee Video "Voucher").
  Widget _buildCouponSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          onTap: _pickCoupons,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.local_offer_outlined,
            color: AppColors.secondary,
          ),
          title: const Text('Voucher'),
          subtitle: Text(
            _coupons.isEmpty
                ? 'Gắn voucher của shop để người xem lấy mã ngay trong video'
                : 'Đã chọn ${_coupons.length} voucher',
            style: const TextStyle(
              fontSize: AppSizes.fontSm,
              color: AppColors.textSecondary,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
        ),
        if (_coupons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.xs),
            child: Wrap(
              spacing: AppSizes.xs,
              runSpacing: AppSizes.xs,
              children: _coupons.map(_buildCouponChip).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildCouponChip(CouponModel c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSizes.sm, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer, size: 13, color: AppColors.secondary),
          const SizedBox(width: 4),
          Text(
            '${c.discountLabel} · ${c.code}',
            style: const TextStyle(
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: () => setState(() => _coupons.remove(c)),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: AppColors.secondary),
            ),
          ),
        ],
      ),
    );
  }
}
