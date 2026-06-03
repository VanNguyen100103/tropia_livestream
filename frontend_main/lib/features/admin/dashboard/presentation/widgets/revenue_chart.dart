import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../data/models/chart_data_model.dart'; // Import Model

class RevenueChart extends StatelessWidget {
  final List<ChartDataModel> chartData; // [MỚI] Nhận dữ liệu

  const RevenueChart({super.key, required this.chartData});

  @override
  Widget build(BuildContext context) {
    // 1. Chuyển đổi dữ liệu API thành FlSpot
    List<FlSpot> spots = [];
    double maxY = 0;

    if (chartData.isNotEmpty) {
      for (int i = 0; i < chartData.length; i++) {
        final item = chartData[i];
        
        // Parse "T1", "T2" -> 1.0, 2.0
        double xValue = i + 1.0; 
        try {
           xValue = double.parse(item.month.replaceAll(RegExp(r'[^0-9]'), ''));
        } catch (_) {}

        // Doanh thu âm -> lấy trị tuyệt đối hoặc để 0 (tuỳ logic, ở đây để 0 cho biểu đồ đẹp)
        double yValue = item.revenue < 0 ? 0 : item.revenue; 
        
        spots.add(FlSpot(xValue, yValue));

        // Tìm Max Y để scale biểu đồ
        if (yValue > maxY) maxY = yValue;
      }
    } else {
        // Dữ liệu giả nếu list rỗng (tránh crash)
        spots = [const FlSpot(0, 0)];
    }

    // Tăng MaxY lên 20% để đỉnh biểu đồ không chạm nóc
    maxY = maxY * 1.2;
    if (maxY == 0) maxY = 1000000; // Default nếu doanh thu toàn 0

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Doanh thu theo tháng",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          
          if (chartData.isEmpty)
             const SizedBox(
               height: 200, 
               child: Center(child: Text("Chưa có dữ liệu"))
             )
          else
            AspectRatio(
              aspectRatio: 1.7,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false, // Tắt dòng dọc cho đỡ rối
                    getDrawingHorizontalLine: (value) => const FlLine(
                      color: Color(0xffe7e8ec),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    
                    // TRỤC X (Tháng)
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1, // Hiển thị từng tháng một
                        getTitlesWidget: (value, meta) {
                          // Chỉ hiện tháng chẵn hoặc lẻ nếu quá dày, ở đây hiện hết
                          int index = value.toInt();
                          if (index >= 1 && index <= 12) {
                             return Padding(
                               padding: const EdgeInsets.only(top: 8.0),
                               child: Text(
                                 "T$index",
                                 style: TextStyle(color: Colors.grey[600], fontSize: 10),
                               ),
                             );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    
                    // TRỤC Y (Doanh thu - Rút gọn số)
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox();
                          
                          String text;
                          if (value >= 1000000000) {
                            text = "${(value / 1000000000).toStringAsFixed(1)}B"; // Tỷ
                          } else if (value >= 1000000) {
                            text = "${(value / 1000000).toStringAsFixed(0)}M"; // Triệu
                          } else {
                            text = "${(value / 1000).toStringAsFixed(0)}K"; // Nghìn
                          }

                          return Text(
                            text,
                            style: TextStyle(color: Colors.grey[600], fontSize: 10),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 1,
                  maxX: 12, // Luôn hiển thị đủ 12 tháng
                  minY: 0,
                  maxY: maxY, // Scale theo doanh thu cao nhất
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.orange,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.orange.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}