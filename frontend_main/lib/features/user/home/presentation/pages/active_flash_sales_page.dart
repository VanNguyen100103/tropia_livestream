import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/features/user/promotions/presentation/promotions_page.dart';

@Deprecated(
  'Moved to PromotionsPage. Update routes to PromotionsPage then delete this file.',
)
class ActiveFlashSalesPage extends StatelessWidget {
  const ActiveFlashSalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Backwards compatibility for existing navigation/routes.
    return const PromotionsPage();
  }
}
