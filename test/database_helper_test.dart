import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/data/models/user_settings_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for headless SQLite testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseHelper dbHelper;

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
  });

  tearDown(() async {
    await dbHelper.close();
  });

  group('DatabaseHelper - App Categories', () {
    test('inserts and retrieves app category correctly', () async {
      const categoryInfo = AppCategoryInfo(
        packageName: 'com.google.android.youtube',
        appName: 'YouTube',
        iconAsset: 'youtube',
        category: AppCategoryType.negative,
      );

      await dbHelper.insertOrUpdateAppCategory(categoryInfo);
      final retrieved = await dbHelper.getAppCategoryByPackageName('com.google.android.youtube');

      expect(retrieved, isNotNull);
      expect(retrieved!.packageName, equals('com.google.android.youtube'));
      expect(retrieved.appName, equals('YouTube'));
      expect(retrieved.category, equals(AppCategoryType.negative));
    });

    test('updates app category classification correctly', () async {
      const initial = AppCategoryInfo(
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        iconAsset: 'whatsapp',
        category: AppCategoryType.neutral,
      );

      await dbHelper.insertOrUpdateAppCategory(initial);
      await dbHelper.updateAppCategory('com.whatsapp', AppCategoryType.productive);

      final updated = await dbHelper.getAppCategoryByPackageName('com.whatsapp');
      expect(updated, isNotNull);
      expect(updated!.category, equals(AppCategoryType.productive));
    });

    test('batch saves and retrieves all categories in order', () async {
      final batchList = [
        const AppCategoryInfo(
          packageName: 'com.a.app',
          appName: 'Alpha App',
          iconAsset: 'a',
          category: AppCategoryType.productive,
        ),
        const AppCategoryInfo(
          packageName: 'com.b.app',
          appName: 'Beta App',
          iconAsset: 'b',
          category: AppCategoryType.negative,
        ),
      ];

      await dbHelper.saveAppCategoriesBatch(batchList);
      final all = await dbHelper.getAllAppCategories();

      expect(all.length, equals(2));
      expect(all.first.appName, equals('Alpha App'));
      expect(all.last.appName, equals('Beta App'));
    });
  });

  group('DatabaseHelper - Usage Records', () {
    test('inserts and retrieves usage records', () async {
      const record = AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: 100000,
        endTime: 200000,
        duration: 100000,
      );

      final id = await dbHelper.insertUsageRecord(record);
      expect(id, greaterThan(0));

      final allRecords = await dbHelper.getAllUsageRecords();
      expect(allRecords.length, equals(1));
      expect(allRecords.first.packageName, equals('com.instagram.android'));
    });

    test('queries usage records by date/time range using overlap semantics (scenarios 1-5)', () async {
      // 1. Fully inside: [5000, 6000]
      const insideRecord = AppUsageRecord(
        packageName: 'com.inside',
        startTime: 5000,
        endTime: 6000,
        duration: 1000,
      );
      // 2. Ending exactly at start boundary: [2000, 4000] (0ms inside range -> excluded)
      const exactBoundaryRecord = AppUsageRecord(
        packageName: 'com.exact.boundary',
        startTime: 2000,
        endTime: 4000,
        duration: 2000,
      );
      // 3. Overlapping start boundary: [3000, 5000]
      const overlapStartRecord = AppUsageRecord(
        packageName: 'com.overlap.start',
        startTime: 3000,
        endTime: 5000,
        duration: 2000,
      );
      // 4. Overlapping end boundary: [6000, 8000]
      const overlapEndRecord = AppUsageRecord(
        packageName: 'com.overlap.end',
        startTime: 6000,
        endTime: 8000,
        duration: 2000,
      );
      // 5. Completely outside (before & after): [1000, 3000] & [8000, 9000]
      const outsideBeforeRecord = AppUsageRecord(
        packageName: 'com.outside.before',
        startTime: 1000,
        endTime: 3000,
        duration: 2000,
      );
      const outsideAfterRecord = AppUsageRecord(
        packageName: 'com.outside.after',
        startTime: 8000,
        endTime: 9000,
        duration: 1000,
      );

      await dbHelper.insertUsageRecord(insideRecord);
      await dbHelper.insertUsageRecord(exactBoundaryRecord);
      await dbHelper.insertUsageRecord(overlapStartRecord);
      await dbHelper.insertUsageRecord(overlapEndRecord);
      await dbHelper.insertUsageRecord(outsideBeforeRecord);
      await dbHelper.insertUsageRecord(outsideAfterRecord);

      final rangeRecords = await dbHelper.getUsageRecordsByDateRange(4000, 7000);
      final packageNames = rangeRecords.map((r) => r.packageName).toList();

      expect(packageNames, containsAll(['com.inside', 'com.overlap.start', 'com.overlap.end']));
      expect(packageNames, isNot(contains('com.exact.boundary')));
      expect(packageNames, isNot(contains('com.outside.before')));
      expect(packageNames, isNot(contains('com.outside.after')));
    });
  });

  group('DatabaseHelper - User Settings', () {
    test('saves and retrieves user settings correctly', () async {
      const settings = UserSettings(
        settingId: 1,
        negativeAppLimit: 45,
        neutralAppLimit: 90,
        productiveAppLimit: -1,
        gracePeriod: 10,
        snoozeEnabled: false,
        snoozeDuration: 10,
        usageLimitsEnabled: true,
      );

      await dbHelper.saveUserSettings(settings);
      final retrieved = await dbHelper.getUserSettings();

      expect(retrieved.negativeAppLimit, equals(45));
      expect(retrieved.neutralAppLimit, equals(90));
      expect(retrieved.gracePeriod, equals(10));
      expect(retrieved.snoozeEnabled, isFalse);
    });

    test('returns default settings when database table is empty', () async {
      final settings = await dbHelper.getUserSettings();

      expect(settings.settingId, equals(1));
      expect(settings.negativeAppLimit, equals(30));
      expect(settings.neutralAppLimit, equals(120));
      expect(settings.productiveAppLimit, equals(-1));
      expect(settings.gracePeriod, equals(5));
      expect(settings.snoozeEnabled, isTrue);
    });
  });
}
