import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/data/models/usage_limit_model.dart';
import 'package:mindgate/services/usage_limit_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('UsageLimitService Unit Tests (Phase 11A)', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late UsageLimitService limitService;

    // Fixed reference time for predictable testing: 2026-09-28 12:00:00.000
    final refNow = DateTime(2026, 9, 28, 12, 0, 0);
    final refTodayStart = DateTime(2026, 9, 28, 0, 0, 0).millisecondsSinceEpoch;

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
      limitService = UsageLimitService(dbHelper: dbHelper);

      // Save standard default user settings
      await dbHelper.saveUserSettings(const UserSettings(
        settingId: 1,
        negativeAppLimit: 30,
        neutralAppLimit: 120,
        productiveAppLimit: -1,
        gracePeriod: 5,
        snoozeEnabled: true,
        snoozeDuration: 5,
        usageLimitsEnabled: true,
      ));
    });

    tearDown(() async {
      await dbHelper.close();
    });

    test('1. Usage limits disabled → no limit reached', () async {
      await dbHelper.saveUserSettings(const UserSettings(
        negativeAppLimit: 30,
        neutralAppLimit: 120,
        productiveAppLimit: -1,
        gracePeriod: 5,
        snoozeEnabled: true,
        usageLimitsEnabled: false, // DISABLED
      ));

      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'instagram',
        category: AppCategoryType.negative,
      ));

      // Insert 50 minutes of negative usage today (limit is 30m)
      const fiftyMinsMs = 50 * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + fiftyMinsMs,
        duration: fiftyMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.instagram.android',
        now: refNow,
      );

      expect(result.status, equals(LimitStatus.notLimited));
      expect(result.isLimitReached, isFalse);
    });

    test('2. Negative category below limit → not reached', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'instagram',
        category: AppCategoryType.negative,
      ));

      // 20 minutes negative usage today (limit is 30m)
      const twentyMinsMs = 20 * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + twentyMinsMs,
        duration: twentyMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.instagram.android',
        now: refNow,
      );

      expect(result.category, equals(AppCategoryType.negative));
      expect(result.categoryLimitMinutes, equals(30));
      expect(result.todayCategoryUsageMinutes, equals(20));
      expect(result.status, equals(LimitStatus.notLimited));
      expect(result.isLimitReached, isFalse);
    });

    test('3. Negative category exactly at limit → reached', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'instagram',
        category: AppCategoryType.negative,
      ));

      // Exactly 30 minutes negative usage today (limit is 30m)
      const thirtyMinsMs = 30 * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + thirtyMinsMs,
        duration: thirtyMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.instagram.android',
        now: refNow,
      );

      expect(result.todayCategoryUsageMinutes, equals(30));
      expect(result.status, equals(LimitStatus.limitReached));
      expect(result.isLimitReached, isTrue);
    });

    test('4. Negative category above limit → reached', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'instagram',
        category: AppCategoryType.negative,
      ));

      // 35 minutes negative usage today (limit is 30m)
      const thirtyFiveMinsMs = 35 * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + thirtyFiveMinsMs,
        duration: thirtyFiveMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.instagram.android',
        now: refNow,
      );

      expect(result.todayCategoryUsageMinutes, equals(35));
      expect(result.status, equals(LimitStatus.limitReached));
      expect(result.isLimitReached, isTrue);
    });

    test('5. Multiple negative apps combined → category total is used', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.google.android.youtube',
        appName: 'YouTube',
        iconAsset: 'youtube',
        category: AppCategoryType.negative,
      ));
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'instagram',
        category: AppCategoryType.negative,
      ));

      const twentyMinsMs = 20 * 60 * 1000;
      const fifteenMinsMs = 15 * 60 * 1000;

      // YouTube = 20 mins, Instagram = 15 mins. Total Negative = 35 mins (limit 30 mins)
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.google.android.youtube',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + twentyMinsMs,
        duration: twentyMinsMs,
      ));
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: refTodayStart + 1000 + twentyMinsMs,
        endTime: refTodayStart + 1000 + twentyMinsMs + fifteenMinsMs,
        duration: fifteenMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.instagram.android',
        now: refNow,
      );

      expect(result.category, equals(AppCategoryType.negative));
      expect(result.todayCategoryUsageMinutes, equals(35));
      expect(result.status, equals(LimitStatus.limitReached));
      expect(result.isLimitReached, isTrue);
    });

    test('6. Neutral category below limit → not reached', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        iconAsset: 'whatsapp',
        category: AppCategoryType.neutral,
      ));

      // 100 minutes neutral usage today (limit is 120m)
      const hundredMinsMs = 100 * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.whatsapp',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + hundredMinsMs,
        duration: hundredMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.whatsapp',
        now: refNow,
      );

      expect(result.category, equals(AppCategoryType.neutral));
      expect(result.categoryLimitMinutes, equals(120));
      expect(result.todayCategoryUsageMinutes, equals(100));
      expect(result.status, equals(LimitStatus.notLimited));
      expect(result.isLimitReached, isFalse);
    });

    test('7. Neutral category at/above limit → reached', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        iconAsset: 'whatsapp',
        category: AppCategoryType.neutral,
      ));

      // 120 minutes neutral usage today (limit is 120m)
      const hundredTwentyMinsMs = 120 * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.whatsapp',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + hundredTwentyMinsMs,
        duration: hundredTwentyMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.whatsapp',
        now: refNow,
      );

      expect(result.todayCategoryUsageMinutes, equals(120));
      expect(result.status, equals(LimitStatus.limitReached));
      expect(result.isLimitReached, isTrue);
    });

    test('8. Productive category with -1 → never reached', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.microsoft.vscode',
        appName: 'VS Code',
        iconAsset: 'vscode',
        category: AppCategoryType.productive,
      ));

      // 500 minutes productive usage today (limit is -1 = unlimited)
      const fiveHundredMinsMs = 500 * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.microsoft.vscode',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + fiveHundredMinsMs,
        duration: fiveHundredMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.microsoft.vscode',
        now: refNow,
      );

      expect(result.category, equals(AppCategoryType.productive));
      expect(result.categoryLimitMinutes, equals(-1));
      expect(result.status, equals(LimitStatus.notLimited));
      expect(result.isLimitReached, isFalse);
    });

    test('9. Unknown category follows existing Neutral behavior', () async {
      // Package not present in app_categories table -> should resolve to Neutral with 120m limit
      const hundredTwentyMinsMs = 120 * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.unknown.app',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + hundredTwentyMinsMs,
        duration: hundredTwentyMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.unknown.app',
        now: refNow,
      );

      expect(result.category, equals(AppCategoryType.neutral));
      expect(result.categoryLimitMinutes, equals(120));
      expect(result.todayCategoryUsageMinutes, equals(120));
      expect(result.status, equals(LimitStatus.limitReached));
      expect(result.isLimitReached, isTrue);
    });

    test('10. Usage from another day does not count toward today\'s limit', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'instagram',
        category: AppCategoryType.negative,
      ));

      final yesterdayStart = DateTime(2026, 9, 27, 10, 0, 0).millisecondsSinceEpoch;
      const sixtyMinsMs = 60 * 60 * 1000;
      const tenMinsMs = 10 * 60 * 1000;

      // 60 minutes yesterday (ignored)
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: yesterdayStart,
        endTime: yesterdayStart + sixtyMinsMs,
        duration: sixtyMinsMs,
      ));

      // 10 minutes today (below 30m limit)
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + tenMinsMs,
        duration: tenMinsMs,
      ));

      final result = await limitService.checkLimitForPackage(
        'com.instagram.android',
        now: refNow,
      );

      expect(result.todayCategoryUsageMinutes, equals(10));
      expect(result.status, equals(LimitStatus.notLimited));
      expect(result.isLimitReached, isFalse);
    });

    test('11. Existing usage records are not modified by limit check', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'instagram',
        category: AppCategoryType.negative,
      ));

      const record = AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: 1000,
        endTime: 61000,
        duration: 60000,
      );
      await dbHelper.insertUsageRecord(record);

      final recordsBefore = await dbHelper.getAllUsageRecords();

      await limitService.checkLimitForPackage(
        'com.instagram.android',
        now: refNow,
      );

      final recordsAfter = await dbHelper.getAllUsageRecords();

      expect(recordsAfter.length, equals(recordsBefore.length));
      expect(recordsAfter.first, equals(recordsBefore.first));
    });

    test('12. Active in-progress foreground session is included in limit detection', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'instagram',
        category: AppCategoryType.negative,
      ));

      // 20 minutes completed negative usage in DB
      const twentyMinsMs = 20 * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: refTodayStart + 1000,
        endTime: refTodayStart + 1000 + twentyMinsMs,
        duration: twentyMinsMs,
      ));

      // Current session started 15 minutes ago (at 11:45 AM, now is 12:00 PM)
      final sessionStart = refNow.subtract(const Duration(minutes: 15)).millisecondsSinceEpoch;

      final result = await limitService.checkLimitForPackage(
        'com.instagram.android',
        now: refNow,
        currentSessionStartTime: sessionStart,
      );

      // Total Negative usage = 20m completed + 15m active = 35m >= 30m limit
      expect(result.todayCategoryUsageMinutes, equals(35));
      expect(result.status, equals(LimitStatus.limitReached));
      expect(result.isLimitReached, isTrue);
    });
  });
}
