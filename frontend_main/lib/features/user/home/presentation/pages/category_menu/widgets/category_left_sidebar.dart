import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/features/user/home/domain/entities/category.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class CategoryLeftSidebar extends StatelessWidget {
  final List<CategoryEntity> categories;
  final int selectedIndex;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener? itemPositionsListener;
  final bool Function(ScrollNotification n)? onScrollNotification;
  final Widget Function(CategoryEntity node, {double size}) buildAvatar;
  final void Function(int index) onTap;

  const CategoryLeftSidebar({
    super.key,
    required this.categories,
    required this.selectedIndex,
    required this.itemScrollController,
    this.itemPositionsListener,
    this.onScrollNotification,
    required this.buildAvatar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidebarWidth = (screenWidth * 0.28).clamp(84.0, 124.0).toDouble();

    return Container(
      width: sidebarWidth,
      color: Colors.white,
      child: NotificationListener<ScrollNotification>(
        onNotification: onScrollNotification,
        child: ScrollablePositionedList.builder(
          itemScrollController: itemScrollController,
          itemPositionsListener: itemPositionsListener,
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final item = categories[index];
            final isSelected = index == selectedIndex;

            return InkWell(
              onTap: () => onTap(index),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFFF3E6) : Colors.white,
                  border: Border(
                    left: BorderSide(
                      color: isSelected
                          ? const Color(0xFFFF8A00)
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    buildAvatar(item, size: 42),
                    const SizedBox(height: 8),
                    Text(
                      item.name,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? const Color(0xFFFF8A00)
                            : Colors.black87,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
