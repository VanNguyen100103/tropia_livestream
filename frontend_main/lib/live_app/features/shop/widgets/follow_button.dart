import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/features/shop/data/shop_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/shop/models/shop_model.dart';

/// Nút Follow / Đang theo dõi cho trang shop.
/// Quản lý state locally, gọi API khi tap.
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.shop,
    this.compact = false,
  });

  final ShopModel shop;
  final bool compact;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  late bool _isFollowing;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.shop.isFollowing;
  }

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);
    final prev = _isFollowing;
    setState(() => _isFollowing = !prev);
    try {
      if (prev) {
        await ShopRepository.instance.unfollow(widget.shop.id);
      } else {
        await ShopRepository.instance.follow(widget.shop.id);
      }
    } catch (_) {
      setState(() => _isFollowing = prev); // rollback
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _buildCompact();
    return _buildFull();
  }

  Widget _buildFull() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _toggle,
        icon: _loading
            ? const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(
                _isFollowing ? Icons.check : Icons.add,
                size: 16,
                color: _isFollowing ? AppColors.textSecondary : AppColors.primary,
              ),
        label: Text(
          _isFollowing ? 'Đang theo dõi' : 'Theo dõi',
          style: TextStyle(
            fontSize: 13,
            color: _isFollowing ? AppColors.textSecondary : AppColors.primary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: _isFollowing ? AppColors.divider : AppColors.primary,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  Widget _buildCompact() {
    return GestureDetector(
      onTap: _loading ? null : _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _isFollowing
              ? AppColors.surfaceVariant
              : AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isFollowing ? AppColors.divider : AppColors.primary,
          ),
        ),
        child: _loading
            ? const SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5))
            : Text(
                _isFollowing ? 'Đang theo dõi' : '+ Theo dõi',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _isFollowing
                      ? AppColors.textSecondary
                      : AppColors.primary,
                ),
              ),
      ),
    );
  }
}
