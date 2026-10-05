import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/app_category_model.dart';

class CategoryPill extends StatelessWidget {
  final AppCategoryType category;
  final bool isDropdown;
  final VoidCallback? onTap;

  const CategoryPill({
    super.key,
    required this.category,
    this.isDropdown = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    Color bgColor;
    Color textColor;

    switch (category) {
      case AppCategoryType.productive:
        label = 'Productive';
        bgColor = AppColors.productiveLight;
        textColor = AppColors.productiveText;
        break;
      case AppCategoryType.neutral:
        label = 'Neutral';
        bgColor = AppColors.neutralLight;
        textColor = AppColors.neutralText;
        break;
      case AppCategoryType.negative:
        label = 'Negative';
        bgColor = AppColors.negativeLight;
        textColor = AppColors.negativeText;
        break;
    }

    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isDropdown) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: textColor,
              size: 16,
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }
    return content;
  }
}
