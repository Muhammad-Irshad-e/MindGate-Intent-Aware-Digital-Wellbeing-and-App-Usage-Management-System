import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/services/app_info_service.dart';

void main() {
  group('AppInfoService Tests', () {
    late AppInfoService service;

    setUp(() {
      service = AppInfoService();
    });

    test('assigns correct default categories for known packages', () {
      expect(
        service.assignDefaultCategory('com.google.android.youtube'),
        equals(AppCategoryType.negative),
      );
      expect(
        service.assignDefaultCategory('com.instagram.android'),
        equals(AppCategoryType.negative),
      );
      expect(
        service.assignDefaultCategory('com.microsoft.vscode'),
        equals(AppCategoryType.productive),
      );
      expect(
        service.assignDefaultCategory('so.notion.app'),
        equals(AppCategoryType.productive),
      );
      expect(
        service.assignDefaultCategory('com.whatsapp'),
        equals(AppCategoryType.neutral),
      );
    });

    test('defaults unknown packages to Neutral category', () {
      expect(
        service.assignDefaultCategory('com.random.unknown.utility'),
        equals(AppCategoryType.neutral),
      );
      expect(
        service.assignDefaultCategory('org.some.custom.app'),
        equals(AppCategoryType.neutral),
      );
    });

    test('falls back gracefully to predefined categories on non-Android platform', () async {
      final categories = await service.getAppCategories();

      expect(categories, isNotEmpty);
      expect(
        categories.any((c) => c.packageName == 'com.google.android.youtube'),
        isTrue,
      );
      expect(
        categories.any((c) => c.packageName == 'com.microsoft.vscode'),
        isTrue,
      );
    });
  });
}
