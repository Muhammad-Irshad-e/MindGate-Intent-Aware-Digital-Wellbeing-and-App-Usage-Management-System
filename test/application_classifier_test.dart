import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_info.dart';
import 'package:mindgate/services/app_info_service.dart';
import 'package:mindgate/services/classifier/application_classifier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_ffi for SQLite testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ApplicationClassifier Unit Tests', () {
    late ApplicationClassifier classifier;

    setUp(() {
      classifier = const HeuristicApplicationClassifier();
    });

    test('1. Classifies known productive applications as Productive', () {
      expect(
        classifier.classify(const AppInfo(
          packageName: 'com.microsoft.vscode',
          appName: 'Visual Studio Code',
        )),
        equals(AppCategoryType.productive),
      );

      expect(
        classifier.classify(const AppInfo(
          packageName: 'so.notion.app',
          appName: 'Notion Notes',
        )),
        equals(AppCategoryType.productive),
      );

      expect(
        classifier.classify(const AppInfo(
          packageName: 'com.custom.duolingostudy',
          appName: 'Language Study',
        )),
        equals(AppCategoryType.productive),
      );
    });

    test('2. Classifies known negative / distracting applications as Negative', () {
      expect(
        classifier.classify(const AppInfo(
          packageName: 'com.google.android.youtube',
          appName: 'YouTube',
        )),
        equals(AppCategoryType.negative),
      );

      expect(
        classifier.classify(const AppInfo(
          packageName: 'com.instagram.android',
          appName: 'Instagram',
        )),
        equals(AppCategoryType.negative),
      );

      expect(
        classifier.classify(const AppInfo(
          packageName: 'com.random.supergame',
          appName: 'Super Poker Game',
        )),
        equals(AppCategoryType.negative),
      );
    });

    test('3. Classifies unknown applications conservatively as Neutral', () {
      expect(
        classifier.classify(const AppInfo(
          packageName: 'com.unknown.utility.calculator',
          appName: 'Custom App 123',
        )),
        equals(AppCategoryType.neutral),
      );

      expect(
        classifier.classify(const AppInfo(
          packageName: 'org.example.customtool',
          appName: 'My Tool',
        )),
        equals(AppCategoryType.neutral),
      );
    });

    test('4. Classifies invalid or empty application information as Neutral', () {
      expect(
        classifier.classify(const AppInfo(
          packageName: '',
          appName: '',
        )),
        equals(AppCategoryType.neutral),
      );

      expect(
        classifier.classify(const AppInfo(
          packageName: '   ',
          appName: '   ',
        )),
        equals(AppCategoryType.neutral),
      );
    });
  });

  group('ApplicationClassifier SQLite & Service Persistence Integration Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late AppInfoService service;

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
      service = AppInfoService(dbHelper: dbHelper);
    });

    tearDown(() async {
      await dbHelper.close();
    });

    test('5. Manual category override remains respected and is not overwritten', () async {
      // 1. Initial classification stored in SQLite for an app (e.g. YouTube classified as Negative)
      const initialCat = AppCategoryInfo(
        packageName: 'com.google.android.youtube',
        appName: 'YouTube',
        iconAsset: 'youtube',
        category: AppCategoryType.negative,
      );
      await dbHelper.insertOrUpdateAppCategory(initialCat);

      // 2. User manually overrides category to Productive
      await service.updateCategory('com.google.android.youtube', AppCategoryType.productive);

      // 3. Verify SQLite DB has updated category to Productive
      final updatedFromDb = await dbHelper.getAppCategoryByPackageName('com.google.android.youtube');
      expect(updatedFromDb, isNotNull);
      expect(updatedFromDb!.category, equals(AppCategoryType.productive));

      // 4. Trigger getAppCategories() which re-fetches or syncs apps
      final categoriesList = await service.getAppCategories();
      final ytEntry = categoriesList.firstWhere((c) => c.packageName == 'com.google.android.youtube');

      // Manual override MUST be preserved
      expect(ytEntry.category, equals(AppCategoryType.productive));
    });

    test('6. Classification result can be persisted through existing SQLite layer', () async {
      const appInfo = AppInfo(
        packageName: 'com.microsoft.vscode',
        appName: 'VS Code',
      );

      final classifiedCategory = service.assignDefaultCategory(appInfo.packageName, appInfo.appName);
      expect(classifiedCategory, equals(AppCategoryType.productive));

      final categoryInfo = AppCategoryInfo(
        packageName: appInfo.packageName,
        appName: appInfo.appName,
        iconAsset: 'vscode',
        category: classifiedCategory,
      );

      await dbHelper.insertOrUpdateAppCategory(categoryInfo);

      final retrieved = await dbHelper.getAppCategoryByPackageName('com.microsoft.vscode');
      expect(retrieved, isNotNull);
      expect(retrieved!.packageName, equals('com.microsoft.vscode'));
      expect(retrieved.category, equals(AppCategoryType.productive));
    });
  });
}
