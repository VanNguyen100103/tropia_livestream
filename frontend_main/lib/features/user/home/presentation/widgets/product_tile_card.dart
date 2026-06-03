import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';

class ProductTileCard extends StatelessWidget {
  final VoidCallback? onTap;
  final String image;
  final String title;
  final Widget price;
  final Widget? originalPrice;
  final Widget action;
  final Widget? imageOverlay;

  final double imageHeight;
  final EdgeInsetsGeometry contentPadding;
  final int titleMaxLines;

  final Border? border;
  final Color backgroundColor;

  const ProductTileCard({
    super.key,
    required this.image,
    required this.title,
    required this.price,
    required this.action,
    this.onTap,
    this.originalPrice,
    this.imageOverlay,
    this.imageHeight = 140,
    this.contentPadding = const EdgeInsets.all(10),
    this.titleMaxLines = 2,
    this.border,
    this.backgroundColor = Colors.white,
  });

  bool _hasValidImage(String value) {
    final v = value.trim();
    return v.isNotEmpty && v != '0';
  }

  @override
  Widget build(BuildContext context) {
    final img = image.trim();
    final hasImage = _hasValidImage(img);
    final isNetwork = hasImage && img.startsWith('http');

    final borderRadius = BorderRadius.circular(12);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: border,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: imageHeight,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.grey[50],
                        child: !hasImage
                            ? const Center(
                                child: Icon(Icons.image, size: 40, color: Colors.grey),
                              )
                            : (isNetwork
                                ? Image.network(
                                    img,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(Icons.broken_image, color: Colors.grey),
                                    ),
                                  )
                                : Image.asset(
                                    img,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(Icons.image, size: 40, color: Colors.grey),
                                    ),
                                  )),
                      ),
                      ?imageOverlay,
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: contentPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: titleMaxLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (originalPrice != null) ...[
                                  originalPrice!,
                                  const SizedBox(height: 2),
                                ],
                                price,
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        action,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
