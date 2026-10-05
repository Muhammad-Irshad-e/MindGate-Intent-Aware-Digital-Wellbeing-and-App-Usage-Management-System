import '../core/utils/system_packages.dart';
import '../data/database/database_helper.dart';
import '../data/models/app_category_model.dart';
import '../data/models/cpi_model.dart';

/// Service responsible for calculating MindGate's Cognitive Productivity Index (CPI).
///
/// ─── CPI Formula ─────────────────────────────────────────────────────────────
///
///           Productive Duration + 0.5 × Neutral Duration
///   CPI = ------------------------------------------------ × 100
///           Productive + Neutral + Negative Duration
///
/// ─── Weighting Rationale ──────────────────────────────────────────────────────
///  • Productive usage contributes fully (1.0×).
///  • Neutral usage contributes half (0.5×).
///  • Negative usage contributes zero (0.0×).
/// ──────────────────────────────────────────────────────────────────────────────
class CpiService {
  final DatabaseHelper _dbHelper;

  CpiService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  /// Calculates the Cognitive Productivity Index for a specific epoch ms time range [[startTime], [endTime]].
  ///
  /// Evaluates persisted usage records from SQLite (excluding system/launcher packages),
  /// associates each record with its stored category, and computes the weighted CPI score.
  Future<CpiResult> calculateCpiForRange(
    int startTime,
    int endTime, {
    String? activePackageName,
    int? currentSessionStartTime,
  }) async {
    try {
      final usageRecords =
          await _dbHelper.getUsageRecordsByDateRange(startTime, endTime);
      final categoriesList = await _dbHelper.getAllAppCategories();

      final categoryMap = {
        for (var cat in categoriesList) cat.packageName: cat.category
      };

      int productiveMs = 0;
      int neutralMs = 0;
      int negativeMs = 0;

      for (final record in usageRecords) {
        if (record.duration <= 0) continue;

        // Filter system packages and OEM launchers
        if (SystemPackages.isSystemPackage(record.packageName)) continue;

        // Calculate portion of session duration that falls inside [startTime, endTime]
        final effectiveStart =
            record.startTime < startTime ? startTime : record.startTime;
        final effectiveEnd =
            record.endTime > endTime ? endTime : record.endTime;
        final clampedDuration = effectiveEnd - effectiveStart;

        if (clampedDuration <= 0) continue;

        // Fallback to Neutral if package category is not stored in SQLite
        final category =
            categoryMap[record.packageName] ?? AppCategoryType.neutral;

        switch (category) {
          case AppCategoryType.productive:
            productiveMs += clampedDuration;
            break;
          case AppCategoryType.neutral:
            neutralMs += clampedDuration;
            break;
          case AppCategoryType.negative:
            negativeMs += clampedDuration;
            break;
        }
      }

      // Account for active in-progress session if provided and not yet in SQLite
      if (activePackageName != null &&
          activePackageName.isNotEmpty &&
          !SystemPackages.isSystemPackage(activePackageName) &&
          currentSessionStartTime != null &&
          currentSessionStartTime < endTime) {
        final isAlreadyPersisted = usageRecords.any((r) =>
            r.packageName == activePackageName &&
            r.startTime == currentSessionStartTime);

        if (!isAlreadyPersisted) {
          final effectiveActiveStart = currentSessionStartTime < startTime
              ? startTime
              : currentSessionStartTime;
          final activeDuration = endTime - effectiveActiveStart;
          if (activeDuration > 0) {
            final category =
                categoryMap[activePackageName] ?? AppCategoryType.neutral;
            switch (category) {
              case AppCategoryType.productive:
                productiveMs += activeDuration;
                break;
              case AppCategoryType.neutral:
                neutralMs += activeDuration;
                break;
              case AppCategoryType.negative:
                negativeMs += activeDuration;
                break;
            }
          }
        }
      }

      final totalMs = productiveMs + neutralMs + negativeMs;

      // Zero-usage handling — return 0% safely
      if (totalMs == 0) {
        return const CpiResult(
          productiveDurationMs: 0,
          neutralDurationMs: 0,
          negativeDurationMs: 0,
          totalDurationMs: 0,
          cpiScore: 0,
        );
      }

      final rawCpi = ((productiveMs + (0.5 * neutralMs)) / totalMs) * 100;
      final clampedCpi = rawCpi.round().clamp(0, 100);

      return CpiResult(
        productiveDurationMs: productiveMs,
        neutralDurationMs: neutralMs,
        negativeDurationMs: negativeMs,
        totalDurationMs: totalMs,
        cpiScore: clampedCpi,
      );
    } catch (e) {
      return const CpiResult(
        productiveDurationMs: 0,
        neutralDurationMs: 0,
        negativeDurationMs: 0,
        totalDurationMs: 0,
        cpiScore: 0,
      );
    }
  }

  /// Calculates the Cognitive Productivity Index for today (midnight → current local time).
  Future<CpiResult> calculateTodayCpi({
    String? activePackageName,
    int? currentSessionStartTime,
  }) async {
    final now = DateTime.now();
    final midnight =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return calculateCpiForRange(
      midnight,
      now.millisecondsSinceEpoch,
      activePackageName: activePackageName,
      currentSessionStartTime: currentSessionStartTime,
    );
  }
}
