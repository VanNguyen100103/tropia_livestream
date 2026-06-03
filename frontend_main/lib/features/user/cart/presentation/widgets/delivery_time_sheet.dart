import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

class DeliveryTimeSheet extends StatefulWidget {
  // Callback trả về ngày và giờ được chọn
  final Function(DateTime selectedDate, String timeSlot) onTimeSelected;

  const DeliveryTimeSheet({super.key, required this.onTimeSelected});

  @override
  State<DeliveryTimeSheet> createState() => _DeliveryTimeSheetState();
}

class _DeliveryTimeSheetState extends State<DeliveryTimeSheet> {
  // 0: Hôm nay, 1: Ngày mai
  int _selectedDateIndex = 0;

  // Mặc định chọn khung giờ đầu tiên
  int _selectedTimeIndex = 0;

  // Tạm ẩn phần chọn loại giao hàng (economy/express). Sau này bật lại.
  static const bool _showServiceTypeSelector = false;

  static const int _startHour = 8;
  static const int _endHour = 19; // slots: 08-09 ... 18-19

  List<String> _buildTimeSlotsForDate(DateTime date) {
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final isToday = day == today;

    int firstHour = _startHour;
    if (isToday) {
      firstHour = now.hour + (now.minute > 0 ? 1 : 0);
      if (firstHour < _startHour) firstHour = _startHour;
    }

    final slots = <String>[];
    for (int h = firstHour; h < _endHour; h++) {
      final start = h.toString().padLeft(2, '0');
      final end = (h + 1).toString().padLeft(2, '0');
      slots.add('$start:00-$end:00');
    }

    return slots;
  }

  List<String> get _currentTimeSlots {
    final slots = _buildTimeSlotsForDate(_currentSelectedDate);
    if (slots.isNotEmpty) return slots;
    if (_selectedDateIndex == 0) return const ["Hôm nay đã hết khung giờ"];
    return const ["Không có khung giờ"];
  }

  // Helper tính ngày thực tế để trả về API
  DateTime get _currentSelectedDate {
    final now = DateTime.now();
    if (_selectedDateIndex == 0) {
      return now; // Hôm nay
    } else {
      return now.add(const Duration(days: 1)); // Ngày mai
    }
  }

  // Helper format ngày hiển thị (VD: 25/11)
  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}";
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Chọn thời gian giao hàng",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 2. Tùy chọn loại giao hàng (tạm ẩn)
          if (_showServiceTypeSelector) ...[
            const ListTile(
              leading: Icon(Icons.radio_button_unchecked, color: Colors.grey),
              title: Text(
                "Giao siêu tốc (Khoảng 45 phút)",
                style: TextStyle(color: Colors.grey),
              ),
              trailing: Text(
                "+9.000đ",
                style: TextStyle(
                  color: Colors.grey,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.radio_button_checked, color: AppColors.primary),
              title: const Text("Giao hàng tiết kiệm (trong 24h)"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "5.000đ ",
                    style: TextStyle(
                      color: Colors.grey[400],
                      decoration: TextDecoration.lineThrough,
                      fontSize: 12,
                    ),
                  ),
                  const Text(
                    "Freeship",
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(thickness: 5, color: Color(0xFFF5F5F5)),
          ],

          // 3. Tab chọn ngày
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Tuỳ chọn khung giờ nhận hàng",
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDateTab(
                        "Hôm nay (${_formatDate(today)})",
                        0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDateTab(
                        "Ngày mai (${_formatDate(tomorrow)})",
                        1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 4. List Khung giờ
          Expanded(
            child: ListView.separated(
              itemCount: _currentTimeSlots.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 50),
              itemBuilder: (context, index) {
                final slot = _currentTimeSlots[index];
                final bool isDisabled =
                    slot.contains("hết khung giờ") ||
                    slot.contains("Không có khung giờ");
                bool isSelected = _selectedTimeIndex == index;
                return ListTile(
                  onTap: isDisabled
                      ? null
                      : () {
                          // Logic: Khi chọn giờ -> Cập nhật state -> Gọi callback -> Đóng popup
                          setState(() => _selectedTimeIndex = index);

                          // Gọi callback trả dữ liệu về CartPage
                          widget.onTimeSelected(_currentSelectedDate, slot);

                          // Đóng Modal sau khi chọn
                          Navigator.pop(context);
                        },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: isDisabled
                      ? const Icon(Icons.block, color: Colors.grey)
                      : isSelected
                      ? const Icon(
                          Icons.radio_button_checked,
                          color: AppColors.primary,
                        )
                      : const Icon(
                          Icons.radio_button_unchecked,
                          color: Colors.grey,
                        ),
                  title: Text(
                    slot,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isDisabled ? Colors.grey : Colors.black87,
                    ),
                  ),
                  trailing: const Text(
                    "Freeship",
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTab(String text, int index) {
    bool isSelected = _selectedDateIndex == index;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedDateIndex = index;
        _selectedTimeIndex = 0;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Colors.white : Colors.grey.shade50,
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? AppColors.primary : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
