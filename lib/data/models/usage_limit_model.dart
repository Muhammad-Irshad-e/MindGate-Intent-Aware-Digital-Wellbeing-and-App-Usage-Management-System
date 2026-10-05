import 'app_category_model.dart';

export 'user_settings_model.dart';

/// Represents the status of a category usage limit check.
enum LimitStatus {
  notLimited,
  limitReached,
}

/// Result of evaluating category usage limits for an application.
class UsageLimitResult {
  final String packageName;
  final AppCategoryType category;
  final int todayCategoryUsageMs;
  final int categoryLimitMinutes;
  final LimitStatus status;

  const UsageLimitResult({
    required this.packageName,
    required this.category,
    required this.todayCategoryUsageMs,
    required this.categoryLimitMinutes,
    required this.status,
  });

  /// True if the limit status is [LimitStatus.limitReached].
  bool get isLimitReached => status == LimitStatus.limitReached;

  /// Today's accumulated category usage converted to whole minutes.
  int get todayCategoryUsageMinutes => todayCategoryUsageMs ~/ 60000;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageLimitResult &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName &&
          category == other.category &&
          todayCategoryUsageMs == other.todayCategoryUsageMs &&
          categoryLimitMinutes == other.categoryLimitMinutes &&
          status == other.status;

  @override
  int get hashCode =>
      packageName.hashCode ^
      category.hashCode ^
      todayCategoryUsageMs.hashCode ^
      categoryLimitMinutes.hashCode ^
      status.hashCode;

  @override
  String toString() =>
      'UsageLimitResult('
      'package: $packageName, '
      'category: ${category.name}, '
      'usageMs: $todayCategoryUsageMs, '
      'limitMins: $categoryLimitMinutes, '
      'status: ${status.name}'
      ')';
}
