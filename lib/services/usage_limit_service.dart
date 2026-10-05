import '../data/database/database_helper.dart';
import '../data/models/app_category_model.dart';
import '../data/models/usage_limit_model.dart';

/// Domain service responsible for detecting when app category usage limits have been reached.
///
/// Features Phase 11A integration:
/// 1. Reads configured category limits and toggle status from SQLite [UserSettings].
/// 2. Resolves package categories from SQLite [AppCategoryInfo] (defaults to [AppCategoryType.neutral]).
/// 3. Computes today's accumulated category usage from SQLite `usage_records`.
/// 4. Accounts for active in-progress foreground session ([currentSessionStartTime]) without modifying DB.
/// 5. Category-based limit enforcement: multiple apps of the same category contribute to the same category total limit.
class UsageLimitService {
  final DatabaseHelper _dbHelper;

  UsageLimitService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  /// Evaluates limit status for [packageName].
  ///
  /// Parameters:
  /// - [packageName]: Package name of the application being evaluated.
  /// - [now]: Reference date/time (defaults to [DateTime.now]).
  /// - [currentSessionStartTime]: Epoch millisecond start timestamp of an active in-progress foreground session.
  Future<UsageLimitResult> checkLimitForPackage(
    String packageName, {
    DateTime? now,
    int? currentSessionStartTime,
  }) async {
    final refNow = now ?? DateTime.now();

    // 1. Resolve category for target package
    final catInfo = await _dbHelper.getAppCategoryByPackageName(packageName);
    final category = catInfo?.category ?? AppCategoryType.neutral;

    // 2. Fetch UserSettings
    final settings = await _dbHelper.getUserSettings();
    final categoryLimitMinutes = _getCategoryLimit(category, settings);

    // 3. Usage limits globally disabled
    if (!settings.usageLimitsEnabled) {
      final usageMs = await getTodayCategoryUsageMs(
        category,
        now: refNow,
        currentSessionStartTime: currentSessionStartTime,
        activePackageName: packageName,
      );
      return UsageLimitResult(
        packageName: packageName,
        category: category,
        todayCategoryUsageMs: usageMs,
        categoryLimitMinutes: categoryLimitMinutes,
        status: LimitStatus.notLimited,
      );
    }

    // 4. Unlimited check (-1)
    if (categoryLimitMinutes == -1) {
      final usageMs = await getTodayCategoryUsageMs(
        category,
        now: refNow,
        currentSessionStartTime: currentSessionStartTime,
        activePackageName: packageName,
      );
      return UsageLimitResult(
        packageName: packageName,
        category: category,
        todayCategoryUsageMs: usageMs,
        categoryLimitMinutes: categoryLimitMinutes,
        status: LimitStatus.notLimited,
      );
    }

    // 5. Calculate today's category usage
    final todayCategoryUsageMs = await getTodayCategoryUsageMs(
      category,
      now: refNow,
      currentSessionStartTime: currentSessionStartTime,
      activePackageName: packageName,
    );

    final categoryLimitMs = categoryLimitMinutes * 60 * 1000;
    final isReached = todayCategoryUsageMs >= categoryLimitMs;

    return UsageLimitResult(
      packageName: packageName,
      category: category,
      todayCategoryUsageMs: todayCategoryUsageMs,
      categoryLimitMinutes: categoryLimitMinutes,
      status: isReached ? LimitStatus.limitReached : LimitStatus.notLimited,
    );
  }

  /// Calculates total usage in milliseconds for [category] during today's calendar day.
  ///
  /// Aggregates completed records from SQLite and accounts for an active unpersisted session.
  Future<int> getTodayCategoryUsageMs(
    AppCategoryType category, {
    DateTime? now,
    int? currentSessionStartTime,
    String? activePackageName,
  }) async {
    final refNow = now ?? DateTime.now();
    final todayMidnight =
        DateTime(refNow.year, refNow.month, refNow.day).millisecondsSinceEpoch;
    final nowEpoch = refNow.millisecondsSinceEpoch;

    final usageRecords =
        await _dbHelper.getUsageRecordsByDateRange(todayMidnight, nowEpoch);
    final categoriesList = await _dbHelper.getAllAppCategories();

    final categoryMap = {
      for (var c in categoriesList) c.packageName: c.category
    };

    int accumulatedMs = 0;

    for (final record in usageRecords) {
      if (record.duration <= 0) continue;

      final recCategory =
          categoryMap[record.packageName] ?? AppCategoryType.neutral;
      if (recCategory == category) {
        final effectiveStart =
            record.startTime < todayMidnight ? todayMidnight : record.startTime;
        final effectiveEnd =
            record.endTime > nowEpoch ? nowEpoch : record.endTime;
        final clampedDuration = effectiveEnd - effectiveStart;
        if (clampedDuration > 0) {
          accumulatedMs += clampedDuration;
        }
      }
    }

    // Account for active in-progress session if provided
    if (currentSessionStartTime != null &&
        currentSessionStartTime < nowEpoch &&
        activePackageName != null &&
        activePackageName.isNotEmpty) {
      final activeCat =
          categoryMap[activePackageName] ?? AppCategoryType.neutral;
      if (activeCat == category) {
        final isAlreadyPersisted = usageRecords.any((r) =>
            r.packageName == activePackageName &&
            r.startTime == currentSessionStartTime);

        if (!isAlreadyPersisted) {
          final effectiveActiveStart =
              currentSessionStartTime < todayMidnight
                  ? todayMidnight
                  : currentSessionStartTime;
          final activeDuration = nowEpoch - effectiveActiveStart;
          if (activeDuration > 0) {
            accumulatedMs += activeDuration;
          }
        }
      }
    }

    return accumulatedMs;
  }

  int _getCategoryLimit(AppCategoryType category, UserSettings settings) {
    switch (category) {
      case AppCategoryType.negative:
        return settings.negativeAppLimit;
      case AppCategoryType.neutral:
        return settings.neutralAppLimit;
      case AppCategoryType.productive:
        return settings.productiveAppLimit;
    }
  }
}
