import 'package:flutter/material.dart';

class ProductItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ProductItemRow({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          // 1. Ảnh + Tên
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      item['image'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.image, size: 20, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // 2. Giá
          Expanded(
            flex: 2,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  "${item['price']}đ",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // 3. Trạng thái
          Expanded(
            flex: 2,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF06F23),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item['status'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 4. Thao tác
          SizedBox(
            width: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: onEdit,
                  child: const Icon(
                    Icons.edit_square,
                    size: 18,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: onDelete,
                  child: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}