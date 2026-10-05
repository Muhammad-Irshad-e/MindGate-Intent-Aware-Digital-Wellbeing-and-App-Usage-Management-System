import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/core/utils/system_packages.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/services/analytics_service.dart';
import 'package:mindgate/services/cpi_service.dart';
import 'package:mindgate/services/usage_monitoring_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int get todayMidnightMs {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseHelper dbHelper;
  late CpiService cpiService;
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
    cpiService = CpiService(dbHelper: dbHelper);
    analyticsService = UsageAnalyticsService(dbHelper: dbHelper, cpiService: cpiService);
  });

  tearDown(() async {
    await db.close();
  });

  group('1. System package exclusion from CPI & Dashboard', () {
    test('CpiService excludes system/launcher/keyboard packages from duration & CPI', () async {
      final start = todayMidnightMs + 1000;

      // Seed 1 hour of Productive user app usage
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.study',
        startTime: start,
        endTime: start + (60 * 60 * 1000),
        duration: 60 * 60 * 1000,
      ));
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.example.study',
        appName: 'Study',
        iconAsset: 'icon',
        category: AppCategoryType.productive,
      ));

      // Seed 10 hours of System UI and Launcher records
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.android.systemui',
        startTime: start,
        endTime: start + (5 * 60 * 60 * 1000),
        duration: 5 * 60 * 60 * 1000,
      ));
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.sec.android.app.launcher',
        startTime: start,
        endTime: start + (5 * 60 * 60 * 1000),
        duration: 5 * 60 * 60 * 1000,
      ));

      final result = await cpiService.calculateCpiForRange(todayMidnightMs, DateTime.now().millisecondsSinceEpoch);

      // System package records must be excluded: total duration should be exactly 1 hour (60 min), NOT 11 hours!
      expect(result.totalMinutes, equals(60));
      expect(result.cpiScore, equals(100)); // 100% productive
    });
  });

  group('2. Active in-progress session inclusion without double counting', () {
    test('Includes active session duration in Today\'s Usage when not yet in SQLite', () async {
      final activeStart = DateTime.now().millisecondsSinceEpoch - (30 * 60 * 1000); // 30 min ago

      final data = await analyticsService.getTodaysUsageData(
        activePackageName: 'com.example.game',
        currentSessionStartTime: activeStart,
      );

      // 30 min active session accounted for
      expect(data.totalMinutes, equals(30));
      expect(data.apps.length, equals(1));
      expect(data.apps.first.packageName, equals('com.example.game'));
      expect(data.apps.first.durationMinutes, equals(30));
    });

    test('Includes active session duration in Dashboard summary and Top Apps', () async {
      final activeStart = DateTime.now().millisecondsSinceEpoch - (45 * 60 * 1000); // 45 min ago

      final data = await analyticsService.getDashboardData(
        activePackageName: 'com.brave.browser',
        currentSessionStartTime: activeStart,
      );

      expect(data.cpiResult.totalMinutes, equals(45));
      expect(data.topApps.length, equals(1));
      expect(data.topApps.first.packageName, equals('com.brave.browser'));
      expect(data.topApps.first.durationMinutes, equals(45));
    });

    test('Does NOT double-count active session once it is persisted in SQLite', () async {
      final activeStart = todayMidnightMs + 1000;
      final activeEnd = activeStart + (30 * 60 * 1000); // 30 min session

      // Record persisted to SQLite when session completed
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.game',
        startTime: activeStart,
        endTime: activeEnd,
        duration: 30 * 60 * 1000,
      ));

      // Query analytics passing the same session parameters
      final data = await analyticsService.getTodaysUsageData(
        activePackageName: 'com.example.game',
        currentSessionStartTime: activeStart,
      );

      // Total duration must be exactly 30 min (NOT 60 min!)
      expect(data.totalMinutes, equals(30));
    });

    test('System UI time is excluded when calculating total user app duration', () async {
      final start = todayMidnightMs + 1000;

      // Session 1: Brave 5 mins
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.brave.browser',
        startTime: start,
        endTime: start + (5 * 60 * 1000),
        duration: 5 * 60 * 1000,
      ));

      // System UI / Notification Shade: 1 min (should be ignored by SystemPackages check)
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.android.systemui',
        startTime: start + (5 * 60 * 1000),
        endTime: start + (6 * 60 * 1000),
        duration: 1 * 60 * 1000,
      ));

      // Session 2: Brave 10 mins after shade collapse
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.brave.browser',
        startTime: start + (6 * 60 * 1000),
        endTime: start + (16 * 60 * 1000),
        duration: 10 * 60 * 1000,
      ));

      final data = await analyticsService.getTodaysUsageData();
      expect(data.totalMinutes, equals(15)); // Exactly 15 mins (not 16 mins)
      expect(data.apps.first.durationMinutes, equals(15));
    });
  });

  group('3. Single DB Writer pattern', () {
    test('processIncomingRecord does not insert duplicates when event arrives', () async {
      final service = UsageMonitoringService(
        dbHelper: dbHelper,
        customRawStream: const Stream.empty(),
      );

      final record = AppUsageRecord(
        packageName: 'com.example.app',
        startTime: todayMidnightMs + 1000,
        endTime: todayMidnightMs + 61000,
        duration: 60000,
      );

      // Native accessibility service persists record first
      await dbHelper.insertUsageRecord(record);

      final initialRecords = await dbHelper.getAllUsageRecords();
      expect(initialRecords.length, equals(1));

      // Dart processIncomingRecord handles event
      await service.processIncomingRecord(record);

      // DB record count must remain 1 (no duplicate inserted)
      final afterRecords = await dbHelper.getAllUsageRecords();
      expect(afterRecords.length, equals(1));

      service.dispose();
    });
  });

  group('4. SystemPackages utility helper', () {
    test('Identifies OEM launchers and system packages', () {
      expect(SystemPackages.isSystemPackage('com.android.systemui'), isTrue);
      expect(SystemPackages.isSystemPackage('com.sec.android.app.launcher'), isTrue);
      expect(SystemPackages.isSystemPackage('com.google.android.apps.nexuslauncher'), isTrue);
      expect(SystemPackages.isSystemPackage('com.instagram.android'), isFalse);
    });
  });
}
