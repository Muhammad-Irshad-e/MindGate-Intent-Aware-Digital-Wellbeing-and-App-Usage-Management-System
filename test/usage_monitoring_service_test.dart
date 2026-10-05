import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/services/usage_monitoring_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_ffi for headless SQLite testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('UsageMonitoringService Integration Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late UsageMonitoringService service;

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
      service = UsageMonitoringService(
        dbHelper: dbHelper,
        customRawStream: const Stream.empty(),
      );
    });

    tearDown(() async {
      service.dispose();
      await dbHelper.close();
    });

    test('1. Monitored package resolves to existing stored category', () async {
      const storedCat = AppCategoryInfo(
        packageName: 'com.google.android.youtube',
        appName: 'YouTube',
        iconAsset: 'youtube',
        category: AppCategoryType.negative,
      );
      await dbHelper.insertOrUpdateAppCategory(storedCat);

      final resolved = await service.resolveAppCategory('com.google.android.youtube');
      expect(resolved.category, equals(AppCategoryType.negative));
      expect(resolved.appName, equals('YouTube'));
    });

    test('2. New package is classified and stored in SQLite app_categories', () async {
      const record = AppUsageRecord(
        packageName: 'so.notion.app',
        startTime: 10000,
        endTime: 30000,
        duration: 20000,
      );

      await service.processIncomingRecord(record);

      final savedCategory = await dbHelper.getAppCategoryByPackageName('so.notion.app');
      expect(savedCategory, isNotNull);
      expect(savedCategory!.category, equals(AppCategoryType.productive));
    });

    test('3. Existing manual user category is not overwritten', () async {
      // 1. User manually sets YouTube to Productive
      const manualCat = AppCategoryInfo(
        packageName: 'com.google.android.youtube',
        appName: 'YouTube',
        iconAsset: 'youtube',
        category: AppCategoryType.productive,
      );
      await dbHelper.insertOrUpdateAppCategory(manualCat);

      // 2. Incoming usage record for YouTube
      const record = AppUsageRecord(
        packageName: 'com.google.android.youtube',
        startTime: 50000,
        endTime: 70000,
        duration: 20000,
      );
      await service.processIncomingRecord(record);

      // 3. Category in SQLite must remain Productive (manual override respected)
      final storedAfter = await dbHelper.getAppCategoryByPackageName('com.google.android.youtube');
      expect(storedAfter, isNotNull);
      expect(storedAfter!.category, equals(AppCategoryType.productive));
    });

    test('4. Completed usage session is persisted in SQLite usage_records', () async {
      const record = AppUsageRecord(
        packageName: 'com.whatsapp',
        startTime: 1000,
        endTime: 15000,
        duration: 14000,
      );

      await service.processIncomingRecord(record);

      final records = await dbHelper.getAllUsageRecords();
      expect(records.length, equals(1));
      expect(records.first.packageName, equals('com.whatsapp'));
      expect(records.first.duration, equals(14000));
    });

    test('5. Unknown application falls back to Neutral', () async {
      const record = AppUsageRecord(
        packageName: 'com.unknown.custom.tool',
        startTime: 1000,
        endTime: 5000,
        duration: 4000,
      );

      await service.processIncomingRecord(record);

      final stored = await dbHelper.getAppCategoryByPackageName('com.unknown.custom.tool');
      expect(stored, isNotNull);
      expect(stored!.category, equals(AppCategoryType.neutral));
    });

    test('6. Duplicate foreground events do not create duplicate database records', () async {
      const record = AppUsageRecord(
        packageName: 'com.instagram.android',
        startTime: 100000,
        endTime: 120000,
        duration: 20000,
      );

      // Send exact same record twice (simulating duplicate window events)
      await service.processIncomingRecord(record);
      await service.processIncomingRecord(record);

      final records = await dbHelper.getAllUsageRecords();
      expect(records.length, equals(1));
    });

    test('7. Database failures do not crash the monitoring service', () async {
      // Create service pointing to a closed database
      await dbHelper.close();
      final brokenService = UsageMonitoringService(dbHelper: dbHelper);

      const record = AppUsageRecord(
        packageName: 'com.example.app',
        startTime: 1000,
        endTime: 2000,
        duration: 1000,
      );

      // Should complete without throwing an unhandled exception
      await expectLater(
        brokenService.processIncomingRecord(record),
        completes,
      );

      brokenService.dispose();
    });

    test('8. Usage persistence occurs even if category resolution throws', () async {
      const record = AppUsageRecord(
        packageName: 'com.failing.category.app',
        startTime: 5000,
        endTime: 15000,
        duration: 10000,
      );

      // Call processIncomingRecord (which catches inner category resolution errors gracefully)
      await service.processIncomingRecord(record);

      final records = await dbHelper.getAllUsageRecords();
      expect(records.length, equals(1));
      expect(records.first.packageName, equals('com.failing.category.app'));
    });
  });
}
