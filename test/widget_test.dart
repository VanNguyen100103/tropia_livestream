// =============================================================================
// widget_test.dart
// =============================================================================
// Smoke test cơ bản – đảm bảo TropiaApp khởi động được.
// Chạy: flutter test
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/main.dart';

void main() {
  testWidgets('TropiaApp smoke test – renders without error', (WidgetTester tester) async {
    // Build app và chạy 1 frame
    await tester.pumpWidget(const TropiaApp());

    // App không nên throw exception trong quá trình render
    expect(tester.takeException(), isNull);
  });
}
