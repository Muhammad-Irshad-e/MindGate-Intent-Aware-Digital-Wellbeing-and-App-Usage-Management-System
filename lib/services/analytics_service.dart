import 'package:flutter/foundation.dart';
import '../core/utils/system_packages.dart';
import '../data/database/database_helper.dart';
import '../data/models/app_category_model.dart';
import '../data/models/app_usage_model.dart';
import '../data/models/cpi_model.dart';
import 'cpi_service.dart';

/// Single app item displayed in Today's Usage detail screen.
class TodaysUsageItem {
  final String appName;
  final String packageName;
  final int durationMinutes;
  final AppCategoryType category;
  final String iconKey;

  const TodaysUsageItem({
    required this.appName,
    required this.packageName,
    required this.durationMinutes,
    required this.category,
    required this.iconKey,
  });

  String get formattedDuration {
    final hours = durationMinutes ~/ 60;
    final mins = durationMinutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}

/// Data object powering Today's Usage detail screen.
class TodaysUsageData {
  final int totalMinutes;
  final List<TodaysUsageItem> apps;

  const TodaysUsageData({
    required this.totalMinutes,
    required this.apps,
  });

  String get formattedTotalTime {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}

/// Comprehensive summary data object powering MindGate's Dashboard Screen.
class DashboardData {
  final CpiResult cpiResult;
  final String cpiStatus;
  final int vsYesterdayPercentage;
  final List<AppUsageItem> topApps;

  const DashboardData({
    required this.cpiResult,
    required this.cpiStatus,
    required this.vsYesterdayPercentage,
    required this.topApps,
  });

  String get formattedTotalTime {
    final totalMins = cpiResult.totalMinutes;
    final hours = totalMins ~/ 60;
    final mins = totalMins % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  int get cpiScore => cpiResult.cpiScore;
  int get productivePercentage => cpiResult.productivePercentage;
  int get neutralPercentage => cpiResult.neutralPercentage;
  int get negativePercentage => cpiResult.negativePercentage;
  int get productiveMinutes => cpiResult.productiveMinutes;
  int get neutralMinutes => cpiResult.neutralMinutes;
  int get negativeMinutes => cpiResult.negativeMinutes;

  String formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}

/// Comprehensive analytics data object powering MindGate's Statistics Screen.
class StatisticsData {
  final int periodIndex; // 0: Day, 1: Weekly, 2: Monthly
  final DateTime referenceDate;
  final String dateLabel;
  final CpiResult cpiResult;
  final List<double> usageTrendBars;
  final List<String> barXLabels;
  final List<double> cpiTrendSpots;
  final List<String> lineXLabels;

  const StatisticsData({
    required this.periodIndex,
    required this.referenceDate,
    required this.dateLabel,
    required this.cpiResult,
    required this.usageTrendBars,
    required this.barXLabels,
    required this.cpiTrendSpots,
    required this.lineXLabels,
  });

  String get formattedTotalTime {
    final totalMins = cpiResult.totalMinutes;
    final hours = totalMins ~/ 60;
    final mins = totalMins % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  int get productivePercentage => cpiResult.productivePercentage;
  int get neutralPercentage => cpiResult.neutralPercentage;
  int get negativePercentage => cpiResult.negativePercentage;
}

/// Provides real-time analytics calculations and aggregation for Dashboard & Statistics screens.
class UsageAnalyticsService {
  final DatabaseHelper _dbHelper;
  final CpiService _cpiService;

  UsageAnalyticsService({
    DatabaseHelper? dbHelper,
    CpiService? cpiService,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _cpiService = cpiService ?? CpiService(dbHelper: dbHelper);

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// Computes real Dashboard summary data for today.
  Future<DashboardData> getDashboardData({
    String? activePackageName,
    int? currentSessionStartTime,
  }) async {
    try {
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final nowEpoch = now.millisecondsSinceEpoch;

      final yesterdayMidnight = DateTime(now.year, now.month, now.day - 1).millisecondsSinceEpoch;

      final todayCpi = await _cpiService.calculateCpiForRange(
        todayMidnight,
        nowEpoch,
        activePackageName: activePackageName,
        currentSessionStartTime: currentSessionStartTime,
      );
      final yesterdayCpi = await _cpiService.calculateCpiForRange(yesterdayMidnight, todayMidnight - 1);

      int vsYesterday = 0;
      if (yesterdayCpi.totalDurationMs > 0) {
        vsYesterday = (((todayCpi.totalDurationMs - yesterdayCpi.totalDurationMs) / yesterdayCpi.totalDurationMs) * 100).round();
      }

      String status = "You're on track!";
      if (todayCpi.cpiScore >= 75) {
        status = "Excellent focus!";
      } else if (todayCpi.cpiScore >= 50) {
        status = "You're on track!";
      } else if (todayCpi.cpiScore > 0) {
        status = "Needs focus";
      } else {
        status = "No usage logged";
      }

      // Fetch today's usage records to build Top Apps list (excluding system packages)
      final usageRecords = await _dbHelper.getUsageRecordsByDateRange(todayMidnight, nowEpoch);
      final categories = await _dbHelper.getAllAppCategories();
      final categoryMap = {for (var c in categories) c.packageName: c};

      final Map<String, int> durationByPackage = {};
      for (final r in usageRecords) {
        if (SystemPackages.isSystemPackage(r.packageName)) continue;
        final effectiveStart = r.startTime < todayMidnight ? todayMidnight : r.startTime;
        final effectiveEnd = r.endTime > nowEpoch ? nowEpoch : r.endTime;
        final clampedDuration = effectiveEnd - effectiveStart;
        if (clampedDuration > 0) {
          durationByPackage[r.packageName] = (durationByPackage[r.packageName] ?? 0) + clampedDuration;
        }
      }

      // Account for active in-progress session if provided and not yet in SQLite
      if (activePackageName != null &&
          activePackageName.isNotEmpty &&
          !SystemPackages.isSystemPackage(activePackageName) &&
          currentSessionStartTime != null &&
          currentSessionStartTime < nowEpoch) {
        final isAlreadyPersisted = usageRecords.any((r) =>
            r.packageName == activePackageName &&
            (r.startTime - currentSessionStartTime).abs() < 1000);

        if (!isAlreadyPersisted) {
          final effectiveActiveStart = currentSessionStartTime < todayMidnight
              ? todayMidnight
              : currentSessionStartTime;
          final activeDuration = nowEpoch - effectiveActiveStart;
          if (activeDuration > 0) {
            durationByPackage[activePackageName] =
                (durationByPackage[activePackageName] ?? 0) + activeDuration;
          }
        }
      }

      final sortedPackages = durationByPackage.keys.toList()
        ..sort((a, b) => durationByPackage[b]!.compareTo(durationByPackage[a]!));

      final List<AppUsageItem> topApps = [];
      for (final pkg in sortedPackages.take(5)) {
        final catInfo = categoryMap[pkg];
        final appName = catInfo?.appName ?? _deriveAppName(pkg);
        final catType = catInfo?.category ?? AppCategoryType.neutral;
        final iconAsset = catInfo?.iconAsset ?? pkg;
        final durationMins = (durationByPackage[pkg]! ~/ 60000);

        topApps.add(AppUsageItem(
          appName: appName,
          packageName: pkg,
          durationMinutes: durationMins,
          category: catType,
          iconKey: iconAsset,
        ));
      }

      return DashboardData(
        cpiResult: todayCpi,
        cpiStatus: status,
        vsYesterdayPercentage: vsYesterday,
        topApps: topApps,
      );
    } catch (e, stack) {
      debugPrint('Error loading dashboard data: $e\n$stack');
      return const DashboardData(
        cpiResult: CpiResult(
          productiveDurationMs: 0,
          neutralDurationMs: 0,
          negativeDurationMs: 0,
          totalDurationMs: 0,
          cpiScore: 0,
        ),
        cpiStatus: "No usage logged",
        vsYesterdayPercentage: 0,
        topApps: [],
      );
    }
  }

  /// Computes detailed usage breakdown for Today's Usage screen.
  ///
  /// Filters out system packages (launcher, honeyboard, etc.) and lists only apps
  /// with actual foreground usage today, sorted by duration descending.
  Future<TodaysUsageData> getTodaysUsageData({
    String? activePackageName,
    int? currentSessionStartTime,
  }) async {
    try {
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final nowEpoch = now.millisecondsSinceEpoch;

      final usageRecords = await _dbHelper.getUsageRecordsByDateRange(todayMidnight, nowEpoch);
      final categories = await _dbHelper.getAllAppCategories();
      final categoryMap = {for (var c in categories) c.packageName: c};

      final Map<String, int> durationByPackage = {};
      for (final r in usageRecords) {
        if (SystemPackages.isSystemPackage(r.packageName)) continue;

        final effectiveStart = r.startTime < todayMidnight ? todayMidnight : r.startTime;
        final effectiveEnd = r.endTime > nowEpoch ? nowEpoch : r.endTime;
        final clampedDuration = effectiveEnd - effectiveStart;
        if (clampedDuration > 0) {
          durationByPackage[r.packageName] = (durationByPackage[r.packageName] ?? 0) + clampedDuration;
        }
      }

      // Account for active in-progress session if provided and not yet in SQLite
      if (activePackageName != null &&
          activePackageName.isNotEmpty &&
          !SystemPackages.isSystemPackage(activePackageName) &&
          currentSessionStartTime != null &&
          currentSessionStartTime < nowEpoch) {
        final isAlreadyPersisted = usageRecords.any((r) =>
            r.packageName == activePackageName &&
            (r.startTime - currentSessionStartTime).abs() < 1000);

        if (!isAlreadyPersisted) {
          final effectiveActiveStart = currentSessionStartTime < todayMidnight
              ? todayMidnight
              : currentSessionStartTime;
          final activeDuration = nowEpoch - effectiveActiveStart;
          if (activeDuration > 0) {
            durationByPackage[activePackageName] =
                (durationByPackage[activePackageName] ?? 0) + activeDuration;
          }
        }
      }

      final sortedPackages = durationByPackage.keys.toList()
        ..sort((a, b) => durationByPackage[b]!.compareTo(durationByPackage[a]!));

      int totalMs = 0;
      final List<TodaysUsageItem> appItems = [];

      for (final pkg in sortedPackages) {
        final durMs = durationByPackage[pkg]!;
        totalMs += durMs;

        final catInfo = categoryMap[pkg];
        final appName = catInfo?.appName ?? _deriveAppName(pkg);
        final catType = catInfo?.category ?? AppCategoryType.neutral;
        final iconAsset = catInfo?.iconAsset ?? pkg;
        final durationMins = durMs ~/ 60000;

        appItems.add(TodaysUsageItem(
          appName: appName,
          packageName: pkg,
          durationMinutes: durationMins,
          category: catType,
          iconKey: iconAsset,
        ));
      }

      return TodaysUsageData(
        totalMinutes: totalMs ~/ 60000,
        apps: appItems,
      );
    } catch (e, stack) {
      debugPrint('Error loading today\'s usage data: $e\n$stack');
      return const TodaysUsageData(totalMinutes: 0, apps: []);
    }
  }

  /// Computes real Statistics data for a given period tab index and reference date.
  ///
  /// periodIndex: 0 = Day, 1 = Weekly, 2 = Monthly
  Future<StatisticsData> getStatisticsData({
    required int periodIndex,
    required DateTime referenceDate,
  }) async {
    try {
      if (periodIndex == 0) {
        return await _getDailyStatistics(referenceDate);
      } else if (periodIndex == 1) {
        return await _getWeeklyStatistics(referenceDate);
      } else {
        return await _getMonthlyStatistics(referenceDate);
      }
    } catch (e, stack) {
      debugPrint('Error loading statistics data: $e\n$stack');
      return _buildEmptyStatistics(periodIndex, referenceDate);
    }
  }

  Future<StatisticsData> _getDailyStatistics(DateTime refDate) async {
    final startOfDay = DateTime(refDate.year, refDate.month, refDate.day, 0, 0, 0).millisecondsSinceEpoch;
    final endOfDay = DateTime(refDate.year, refDate.month, refDate.day, 23, 59, 59, 999).millisecondsSinceEpoch;

    final cpiResult = await _cpiService.calculateCpiForRange(startOfDay, endOfDay);
    final dateLabel = '${refDate.day} ${_monthNames[refDate.month - 1]} ${refDate.year}';

    // 6 time slots of 4 hours each: 0-4, 4-8, 8-12, 12-16, 16-20, 20-24
    final List<double> usageBars = [];
    final List<double> cpiSpots = [];

    for (int i = 0; i < 6; i++) {
      final slotStart = DateTime(refDate.year, refDate.month, refDate.day, i * 4, 0).millisecondsSinceEpoch;
      final slotEnd = DateTime(refDate.year, refDate.month, refDate.day, (i * 4) + 3, 59, 59, 999).millisecondsSinceEpoch;

      final slotCpi = await _cpiService.calculateCpiForRange(slotStart, slotEnd);
      usageBars.add(slotCpi.totalMinutes.toDouble());
      cpiSpots.add(slotCpi.cpiScore.toDouble());
    }

    return StatisticsData(
      periodIndex: 0,
      referenceDate: refDate,
      dateLabel: dateLabel,
      cpiResult: cpiResult,
      usageTrendBars: usageBars,
      barXLabels: const ['12 AM', '4 AM', '8 AM', '12 PM', '4 PM', '8 PM'],
      cpiTrendSpots: cpiSpots,
      lineXLabels: const ['12 AM', '4 AM', '8 AM', '12 PM', '4 PM', '8 PM'],
    );
  }

  Future<StatisticsData> _getWeeklyStatistics(DateTime refDate) async {
    // Find Monday of the week
    final monday = refDate.subtract(Duration(days: refDate.weekday - 1));
    final mondayStart = DateTime(monday.year, monday.month, monday.day, 0, 0, 0).millisecondsSinceEpoch;
    final sunday = monday.add(const Duration(days: 6));
    final sundayEnd = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59, 999).millisecondsSinceEpoch;

    final cpiResult = await _cpiService.calculateCpiForRange(mondayStart, sundayEnd);
    final dateLabel = '${monday.day} ${_monthNames[monday.month - 1]} - ${sunday.day} ${_monthNames[sunday.month - 1]} ${sunday.year}';

    final List<double> usageBars = [];
    final List<double> cpiSpots = [];

    for (int i = 0; i < 7; i++) {
      final dayDate = monday.add(Duration(days: i));
      final dayStart = DateTime(dayDate.year, dayDate.month, dayDate.day, 0, 0, 0).millisecondsSinceEpoch;
      final dayEnd = DateTime(dayDate.year, dayDate.month, dayDate.day, 23, 59, 59, 999).millisecondsSinceEpoch;

      final dayCpi = await _cpiService.calculateCpiForRange(dayStart, dayEnd);
      usageBars.add(dayCpi.totalMinutes.toDouble());
      cpiSpots.add(dayCpi.cpiScore.toDouble());
    }

    return StatisticsData(
      periodIndex: 1,
      referenceDate: refDate,
      dateLabel: dateLabel,
      cpiResult: cpiResult,
      usageTrendBars: usageBars,
      barXLabels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      cpiTrendSpots: cpiSpots,
      lineXLabels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    );
  }

  Future<StatisticsData> _getMonthlyStatistics(DateTime refDate) async {
    final monthStart = DateTime(refDate.year, refDate.month, 1, 0, 0, 0).millisecondsSinceEpoch;
    final nextMonth = refDate.month == 12 ? DateTime(refDate.year + 1, 1, 1) : DateTime(refDate.year, refDate.month + 1, 1);
    final monthEnd = nextMonth.subtract(const Duration(milliseconds: 1)).millisecondsSinceEpoch;

    final cpiResult = await _cpiService.calculateCpiForRange(monthStart, monthEnd);
    final dateLabel = '${_monthNames[refDate.month - 1]} ${refDate.year}';

    // Group into 4 weeks of ~7 days
    final List<double> usageBars = [];
    final List<double> cpiSpots = [];

    for (int i = 0; i < 4; i++) {
      final weekStartDay = (i * 7) + 1;
      final weekEndDay = (i == 3) ? DateTime(refDate.year, refDate.month + 1, 0).day : (i + 1) * 7;

      final wStart = DateTime(refDate.year, refDate.month, weekStartDay, 0, 0, 0).millisecondsSinceEpoch;
      final wEnd = DateTime(refDate.year, refDate.month, weekEndDay, 23, 59, 59, 999).millisecondsSinceEpoch;

      final wCpi = await _cpiService.calculateCpiForRange(wStart, wEnd);
      usageBars.add(wCpi.totalMinutes.toDouble());
      cpiSpots.add(wCpi.cpiScore.toDouble());
    }

    return StatisticsData(
      periodIndex: 2,
      referenceDate: refDate,
      dateLabel: dateLabel,
      cpiResult: cpiResult,
      usageTrendBars: usageBars,
      barXLabels: const ['W1', 'W2', 'W3', 'W4'],
      cpiTrendSpots: cpiSpots,
      lineXLabels: const ['W1', 'W2', 'W3', 'W4'],
    );
  }

  StatisticsData _buildEmptyStatistics(int periodIndex, DateTime refDate) {
    return StatisticsData(
      periodIndex: periodIndex,
      referenceDate: refDate,
      dateLabel: '${refDate.day} ${_monthNames[refDate.month - 1]} ${refDate.year}',
      cpiResult: const CpiResult(
        productiveDurationMs: 0,
        neutralDurationMs: 0,
        negativeDurationMs: 0,
        totalDurationMs: 0,
        cpiScore: 0,
      ),
      usageTrendBars: const [0, 0, 0, 0, 0, 0],
      barXLabels: const ['12 AM', '4 AM', '8 AM', '12 PM', '4 PM', '8 PM'],
      cpiTrendSpots: const [0, 0, 0, 0, 0, 0],
      lineXLabels: const ['12 AM', '4 AM', '8 AM', '12 PM', '4 PM', '8 PM'],
    );
  }

  static String _deriveAppName(String packageName) {
    if (packageName.isEmpty) return 'Unknown App';
    final parts = packageName.split('.');
    if (parts.isNotEmpty) {
      final last = parts.last;
      if (last.isNotEmpty) {
        return last[0].toUpperCase() + last.substring(1);
      }
    }
    return packageName;
  }
}
