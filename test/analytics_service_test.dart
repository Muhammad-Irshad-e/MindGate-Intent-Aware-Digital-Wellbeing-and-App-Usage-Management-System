import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/services/analytics_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_ffi for SQLite testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('UsageAnalyticsService Unit Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late UsageAnalyticsService analyticsService;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE ${DatabaseHelper.tableAppCategories} (
              packageName TEXT PRIMARY KEY,
              appName TEXT NOT NULL,
              iconAsset TEXT NOT NULL,
              category TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE ${DatabaseHelper.tableUsageRecords} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              packageName TEXT NOT NULL,
              startTime INTEGER NOT NULL,
              endTime INTEGER NOT NULL,
              duration INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE ${DatabaseHelper.tableUserSettings} (
              settingId INTEGER PRIMARY KEY,
              negativeAppLimit INTEGER NOT NULL,
              neutralAppLimit INTEGER NOT NULL,
              productiveAppLimit INTEGER NOT NULL,
              gracePeriod INTEGER NOT NULL,
              snoozeEnabled INTEGER NOT NULL,
              snoozeDuration INTEGER NOT NULL,
              usageLimitsEnabled INTEGER NOT NULL
            )
          ''');
        },
      );
      dbHelper = DatabaseHelper.withDatabase(db);
      analyticsService = UsageAnalyticsService(dbHelper: dbHelper);
    });

    tearDown(() async {
      await dbHelper.close();
    });

    test('1. Dashboard today total usage calculation & 2. category totals', () async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 1, 0, 0).millisecondsSinceEpoch;

      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.prod.app',
        appName: 'Productive App',
        iconAsset: 'prod',
        category: AppCategoryType.productive,
      ));

      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.prod.app',
        startTime: todayStart,
        endTime: todayStart + 3600000,
        duration: 3600000, // 60 mins
      ));

      final dashboard = await analyticsService.getDashboardData();

      expect(dashboard.productiveMinutes, equals(60));
      expect(dashboard.cpiResult.totalMinutes, equals(60));
      expect(dashboard.productivePercentage, equals(100));
    });

    test('3. Dashboard CPI value comes from CpiService', () async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 1, 0, 0).millisecondsSinceEpoch;

      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.prod.app',
        appName: 'Productive App',
        iconAsset: 'prod',
        category: AppCategoryType.productive,
      ));

      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.prod.app',
        startTime: todayStart,
        endTime: todayStart + 3600000,
        duration: 3600000,
      ));

      final dashboard = await analyticsService.getDashboardData();
      expect(dashboard.cpiScore, equals(100));
    });

    test('4. Top Apps ordering by duration', () async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 1, 0, 0).millisecondsSinceEpoch;

      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.less.used',
        appName: 'Less Used',
        iconAsset: 'less',
        category: AppCategoryType.neutral,
      ));
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.more.used',
        appName: 'More Used',
        iconAsset: 'more',
        category: AppCategoryType.productive,
      ));

      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.less.used',
        startTime: todayStart,
        endTime: todayStart + 600000,
        duration: 600000, // 10m
      ));

      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.more.used',
        startTime: todayStart + 600000,
        endTime: todayStart + 3600000,
        duration: 3000000, // 50m
      ));

      final dashboard = await analyticsService.getDashboardData();
      expect(dashboard.topApps.length, equals(2));
      expect(dashboard.topApps.first.packageName, equals('com.more.used'));
      expect(dashboard.topApps.last.packageName, equals('com.less.used'));
    });

    test('5. Empty usage data returns safe zero values without crashing', () async {
      final dashboard = await analyticsService.getDashboardData();

      expect(dashboard.cpiScore, equals(0));
      expect(dashboard.cpiResult.totalMinutes, equals(0));
      expect(dashboard.topApps, isEmpty);
    });

    test('6. Day statistics for selected date', () async {
      final selectedDate = DateTime(2025, 4, 24);
      final dayStart = DateTime(2025, 4, 24, 10, 0, 0).millisecondsSinceEpoch;

      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.day.app',
        appName: 'Day App',
        iconAsset: 'day',
        category: AppCategoryType.productive,
      ));

      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.day.app',
        startTime: dayStart,
        endTime: dayStart + 1800000,
        duration: 1800000, // 30m
      ));

      final stats = await analyticsService.getStatisticsData(
        periodIndex: 0,
        referenceDate: selectedDate,
      );

      expect(stats.dateLabel, equals('24 Apr 2025'));
      expect(stats.cpiResult.totalMinutes, equals(30));
    });

    test('7. Weekly aggregation (Monday-Sunday)', () async {
      final selectedDate = DateTime(2025, 4, 23); // Wednesday

      final stats = await analyticsService.getStatisticsData(
        periodIndex: 1,
        referenceDate: selectedDate,
      );

      expect(stats.periodIndex, equals(1));
      expect(stats.usageTrendBars.length, equals(7)); // 7 days Mon-Sun
      expect(stats.cpiTrendSpots.length, equals(7));
    });

    test('8. Monthly aggregation', () async {
      final selectedDate = DateTime(2025, 4, 15);

      final stats = await analyticsService.getStatisticsData(
        periodIndex: 2,
        referenceDate: selectedDate,
      );

      expect(stats.periodIndex, equals(2));
      expect(stats.dateLabel, equals('Apr 2025'));
      expect(stats.usageTrendBars.length, equals(4)); // 4 weeks
    });

    test('9. Category aggregation using packageName & 10. Unknown package fallback to Neutral', () async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 2, 0, 0).millisecondsSinceEpoch;

      // Usage record for an unknown package not present in app_categories table
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.unknown.pkg',
        startTime: todayStart,
        endTime: todayStart + 1200000,
        duration: 1200000, // 20m
      ));

      final dashboard = await analyticsService.getDashboardData();

      // Fallback is Neutral
      expect(dashboard.neutralMinutes, equals(20));
      expect(dashboard.productiveMinutes, equals(0));
    });

    test('11. Trend data generation produces valid bar and spot lists', () async {
      final stats = await analyticsService.getStatisticsData(
        periodIndex: 0,
        referenceDate: DateTime.now(),
      );

      expect(stats.usageTrendBars.length, equals(6));
      expect(stats.cpiTrendSpots.length, equals(6));
      expect(stats.barXLabels.length, equals(6));
    });

    test('12. No database crash on empty/error conditions', () async {
      await dbHelper.close();

      final brokenAnalytics = UsageAnalyticsService(dbHelper: dbHelper);
      final dashboard = await brokenAnalytics.getDashboardData();

      expect(dashboard.cpiScore, equals(0));
      expect(dashboard.topApps, isEmpty);
    });

    test('13. getTodaysUsageData excludes system UI packages and orders by duration descending', () async {
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

      // Insert category info
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.google.android.youtube',
        appName: 'YouTube',
        iconAsset: 'youtube',
        category: AppCategoryType.negative,
      ));
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'so.notion.app',
        appName: 'Notion',
        iconAsset: 'notion',
        category: AppCategoryType.productive,
      ));

      // Insert usage records: YouTube (40m), Notion (15m), System UI Launcher (30m - should be excluded)
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.google.android.youtube',
        startTime: todayMidnight + 1000,
        endTime: todayMidnight + 2401000,
        duration: 2400000, // 40m
      ));
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'so.notion.app',
        startTime: todayMidnight + 3000000,
        endTime: todayMidnight + 3900000,
        duration: 900000, // 15m
      ));
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.sec.android.app.launcher',
        startTime: todayMidnight + 4000000,
        endTime: todayMidnight + 5800000,
        duration: 1800000, // 30m - system package
      ));

      final todaysUsage = await analyticsService.getTodaysUsageData();

      // System launcher excluded, so 2 apps remain
      expect(todaysUsage.apps.length, equals(2));

      // First app: YouTube (40m)
      expect(todaysUsage.apps[0].packageName, equals('com.google.android.youtube'));
      expect(todaysUsage.apps[0].durationMinutes, equals(40));

      // Second app: Notion (15m)
      expect(todaysUsage.apps[1].packageName, equals('so.notion.app'));
      expect(todaysUsage.apps[1].durationMinutes, equals(15));

      // Total usage: 55m
      expect(todaysUsage.totalMinutes, equals(55));
    });
  });
}
