import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/services/cpi_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_ffi for SQLite testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('CpiService Unit Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late CpiService cpiService;

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
    });

    tearDown(() async {
      await dbHelper.close();
    });

    test('1. 100% productive usage calculates to CPI 100', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.microsoft.vscode',
        appName: 'VS Code',
        iconAsset: 'vscode',
        category: AppCategoryType.productive,
      ));

      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.microsoft.vscode',
        startTime: 1000,
        endTime: 61000,
        duration: 60000, // 60s productive
      ));

      final result = await cpiService.calculateCpiForRange(0, 100000);

      expect(result.cpiScore, equals(100));
      expect(result.productiveMinutes, equals(1));
      expect(result.neutralMinutes, equals(0));
      expect(result.negativeMinutes, equals(0));
      expect(result.productivePercentage, equals(100));
    });

    test('2. 100% neutral usage calculates to CPI 50', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        iconAsset: 'whatsapp',
        category: AppCategoryType.neutral,
      ));

      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.whatsapp',
        startTime: 1000,
        endTime: 61000,
        duration: 60000, // 60s neutral
      ));

      final result = await cpiService.calculateCpiForRange(0, 100000);

      expect(result.cpiScore, equals(50));
      expect(result.neutralPercentage, equals(100));
    });

    test('3. 100% negative usage calculates to CPI 0', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'instagram',
        category: AppCategoryType.negative,
      ));

      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: 1000,
        endTime: 61000,
        duration: 60000, // 60s negative
      ));

      final result = await cpiService.calculateCpiForRange(0, 100000);

      expect(result.cpiScore, equals(0));
      expect(result.negativePercentage, equals(100));
    });

    test('4. Mixed usage calculates correctly (60m prod, 20m neutral, 20m neg -> CPI 70)', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.prod',
        appName: 'Prod',
        iconAsset: 'p',
        category: AppCategoryType.productive,
      ));
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.neut',
        appName: 'Neut',
        iconAsset: 'n',
        category: AppCategoryType.neutral,
      ));
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.neg',
        appName: 'Neg',
        iconAsset: 'ng',
        category: AppCategoryType.negative,
      ));

      const hourMs = 3600000;
      const twentyMinMs = 1200000;

      // 60m productive, 20m neutral, 20m negative = 100m total
      // CPI = (60 + 0.5 * 20) / 100 * 100 = 70%
      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.prod',
        startTime: 1000,
        endTime: 1000 + hourMs,
        duration: hourMs,
      ));
      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.neut',
        startTime: 1000 + hourMs,
        endTime: 1000 + hourMs + twentyMinMs,
        duration: twentyMinMs,
      ));
      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.neg',
        startTime: 1000 + hourMs + twentyMinMs,
        endTime: 1000 + hourMs + 2 * twentyMinMs,
        duration: twentyMinMs,
      ));

      final result = await cpiService.calculateCpiForRange(0, 10000000);

      expect(result.cpiScore, equals(70));
      expect(result.productiveMinutes, equals(60));
      expect(result.neutralMinutes, equals(20));
      expect(result.negativeMinutes, equals(20));
      expect(result.totalMinutes, equals(100));
    });

    test('5. Zero usage does not cause division by zero and returns CPI 0', () async {
      final result = await cpiService.calculateCpiForRange(0, 100000);

      expect(result.cpiScore, equals(0));
      expect(result.totalDurationMs, equals(0));
      expect(result.productivePercentage, equals(0));
    });

    test('6. CPI score never exceeds 100', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.prod',
        appName: 'Prod',
        iconAsset: 'p',
        category: AppCategoryType.productive,
      ));

      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.prod',
        startTime: 1000,
        endTime: 1000000,
        duration: 999000,
      ));

      final result = await cpiService.calculateCpiForRange(0, 2000000);

      expect(result.cpiScore, lessThanOrEqualTo(100));
      expect(result.cpiScore, equals(100));
    });

    test('7. CPI score never goes below 0', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.neg',
        appName: 'Neg',
        iconAsset: 'n',
        category: AppCategoryType.negative,
      ));

      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.neg',
        startTime: 1000,
        endTime: 1000000,
        duration: 999000,
      ));

      final result = await cpiService.calculateCpiForRange(0, 2000000);

      expect(result.cpiScore, greaterThanOrEqualTo(0));
      expect(result.cpiScore, equals(0));
    });

    test('8. Time-range filtering works correctly', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.prod',
        appName: 'Prod',
        iconAsset: 'p',
        category: AppCategoryType.productive,
      ));

      // Record outside query range
      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.prod',
        startTime: 100,
        endTime: 500,
        duration: 400,
      ));

      // Record inside query range
      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.prod',
        startTime: 5000,
        endTime: 10000,
        duration: 5000,
      ));

      final result = await cpiService.calculateCpiForRange(4000, 12000);

      expect(result.totalDurationMs, equals(5000));
      expect(result.cpiScore, equals(100));
    });

    test('9. Category lookup by packageName correlates correctly', () async {
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.google.android.youtube',
        appName: 'YouTube',
        iconAsset: 'youtube',
        category: AppCategoryType.negative,
      ));

      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.google.android.youtube',
        startTime: 1000,
        endTime: 5000,
        duration: 4000,
      ));

      final result = await cpiService.calculateCpiForRange(0, 10000);

      expect(result.negativeDurationMs, equals(4000));
      expect(result.cpiScore, equals(0));
    });

    test('10. Unknown package/category follows documented fallback (Neutral)', () async {
      // Record for a package not present in app_categories table
      await dbHelper.insertUsageRecord(const AppUsageRecord(
        packageName: 'com.unknown.app',
        startTime: 1000,
        endTime: 61000,
        duration: 60000, // 60s unknown app
      ));

      final result = await cpiService.calculateCpiForRange(0, 100000);

      // Unknown package treated as Neutral -> 100% neutral -> CPI 50
      expect(result.neutralDurationMs, equals(60000));
      expect(result.cpiScore, equals(50));
    });
  });
}
