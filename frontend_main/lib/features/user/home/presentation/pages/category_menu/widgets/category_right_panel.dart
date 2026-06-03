import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tropia_mobile_app_android/features/user/home/domain/entities/category.dart';
// Import Grid vừa tách
import 'category_grid.dart';

class CategoryRightPanel extends StatelessWidget {
  final ItemScrollController itemScrollController;
  final ItemPositionsListener? itemPositionsListener;
  final List<CategoryEntity> roots;
  final int activeLevel1Index;
  final Widget Function(CategoryEntity node, {double size}) buildAvatar;
  final void Function(CategoryEntity node) onTapCategory;
  final void Function(CategoryEntity node) onViewAll;
  final VoidCallback? onScrollEnd;
  final bool Function(ScrollNotification n)? onScrollNotification;

  const CategoryRightPanel({
    super.key,
    required this.itemScrollController,
    this.itemPositionsListener,
    required this.roots,
    required this.activeLevel1Index,
    required this.buildAvatar,
    required this.onTapCategory,
    required this.onViewAll,
    this.onScrollEnd,
    this.onScrollNotification,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F8FB),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          final handled = onScrollNotification?.call(n) ?? false;
          if (handled) return true;
          if (n is ScrollEndNotification) {
            onScrollEnd?.call();
          }
          return false;
        },
        child: ScrollablePositionedList.builder(
          itemScrollController: itemScrollController,
          itemPositionsListener: itemPositionsListener,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          itemCount: roots.length,
          itemBuilder: (context, index) {
            final level1 = roots[index];
            final level2List = level1.children;
            final isActive = index == activeLevel1Index;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          level1.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isActive
                                ? const Color(0xFFFF8A00)
                                : const Color(0xFF333333),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => onViewAll(level1),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Xem tất cả',
                          style: TextStyle(
                            color: Color(0xFFFF8A00),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (level2List.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: CategoryGrid(
                        nodes: <CategoryEntity>[level1],
                        buildAvatar: buildAvatar,
                        onTap: onTapCategory,
                      ),
                    )
                  else
                    ...level2List.map((level2) {
                      final level3 = level2.children;
                      final gridNodes = level3.isNotEmpty
                          ? level3
                          : <CategoryEntity>[level2];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    level2.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () => onViewAll(level2),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Xem tất cả',
                                    style: TextStyle(
                                      color: Color(0xFFFF8A00),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Sử dụng CategoryGrid ở đây
                            CategoryGrid(
                              nodes: gridNodes,
                              buildAvatar: buildAvatar,
                              onTap: onTapCategory,
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
