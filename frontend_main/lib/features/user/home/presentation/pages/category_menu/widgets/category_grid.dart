import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/features/user/home/domain/entities/category.dart';

class CategoryGrid extends StatelessWidget {
  final List<CategoryEntity> nodes;
  final Widget Function(CategoryEntity node, {double size}) buildAvatar;
  final void Function(CategoryEntity node) onTap;

  const CategoryGrid({
    super.key,
    required this.nodes,
    required this.buildAvatar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossAxisCount = w < 360
            ? 2
            : w < 600
            ? 3
            : 4;
        final avatarSize = crossAxisCount == 2 ? 58.0 : 54.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: nodes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: avatarSize + 70, // Padding(20) + SizedBox(8) + Text(3 lines ~42) = 70
          ),
          itemBuilder: (context, index) {
            final item = nodes[index];
            return InkWell(
              onTap: () => onTap(item),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    buildAvatar(item, size: avatarSize),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Text(
                        item.name,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF333333),
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
