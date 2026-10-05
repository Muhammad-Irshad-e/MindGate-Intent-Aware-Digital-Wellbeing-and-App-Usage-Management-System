import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/data/models/intervention_state_model.dart';
import 'package:mindgate/data/models/user_settings_model.dart';
import 'package:mindgate/services/intervention_service.dart';
import 'package:mindgate/services/usage_limit_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('InterventionState & InterventionService Unit Tests (Phase 11B)', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late UsageLimitService limitService;
    late InterventionService interventionService;

    final refNow = DateTime(2026, 9, 29, 10, 0, 0);
    final refTodayStart =
        DateTime(2026, 9, 29, 0, 0, 0).millisecondsSinceEpoch;

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
      interventionService = InterventionService(
        limitService: limitService,
        dbHelper: dbHelper,
      );

      // Default user settings: negative limit 30m, grace 5m, snooze enabled 5m
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

      // Category setup: app1 is negative category
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.example.app1',
        appName: 'Test Negative App',
        iconAsset: 'com.example.app1',
        category: AppCategoryType.negative,
      ));
    });

    tearDown(() async {
      await db.close();
    });

    test('1. Limit reached starts grace period', () async {
      // Add 35 minutes usage for negative category (limit is 30)
      final startMs = refTodayStart + 1000;
      final endMs = startMs + (35 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      final state = await interventionService.evaluatePackage(
        'com.example.app1',
        now: refNow,
      );

      expect(state, isNotNull);
      expect(state!.packageName, equals('com.example.app1'));
      expect(state.category, equals(AppCategoryType.negative));
      expect(state.isSnoozed, isFalse);
      expect(state.getStatusAt(refNow), equals(InterventionStatus.gracePeriod));
    });

    test('2. Limit not reached does not start intervention', () async {
      // Add 15 minutes usage for negative category (limit is 30)
      final startMs = refTodayStart + 1000;
      final endMs = startMs + (15 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      final state = await interventionService.evaluatePackage(
        'com.example.app1',
        now: refNow,
      );

      expect(state, isNull);
      expect(interventionService.currentState, isNull);
      expect(
        interventionService.getCurrentStatus(now: refNow),
        equals(InterventionStatus.none),
      );
    });

    test('3. Grace period uses configured duration', () async {
      // Save settings with 10-minute grace period
      await dbHelper.saveUserSettings(const UserSettings(
        negativeAppLimit: 30,
        neutralAppLimit: 120,
        productiveAppLimit: -1,
        gracePeriod: 10,
        snoozeEnabled: true,
        snoozeDuration: 5,
        usageLimitsEnabled: true,
      ));

      final startMs = refTodayStart + 1000;
      final endMs = startMs + (35 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      final state = await interventionService.evaluatePackage(
        'com.example.app1',
        now: refNow,
      );

      expect(state, isNotNull);
      expect(state!.graceStartTime, equals(refNow));
      expect(state.graceEndTime, equals(refNow.add(const Duration(minutes: 10))));
      expect(state.remainingGraceSeconds(refNow), equals(600));
    });

    test('4. Take a Break clears intervention state', () async {
      final startMs = refTodayStart + 1000;
      final endMs = startMs + (35 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      await interventionService.evaluatePackage(
        'com.example.app1',
        now: refNow,
      );
      expect(interventionService.currentState, isNotNull);

      interventionService.takeABreak();

      expect(interventionService.currentState, isNull);
      expect(
        interventionService.getCurrentStatus(now: refNow),
        equals(InterventionStatus.none),
      );
    });

    test('5. Snooze starts when enabled', () async {
      final startMs = refTodayStart + 1000;
      final endMs = startMs + (35 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      await interventionService.evaluatePackage(
        'com.example.app1',
        now: refNow,
      );

      final snoozed = await interventionService.snooze(now: refNow);

      expect(snoozed, isTrue);
      expect(interventionService.currentState!.isSnoozed, isTrue);
      expect(
        interventionService.getCurrentStatus(now: refNow),
        equals(InterventionStatus.snoozed),
      );
    });

    test('6. Snooze does not start when disabled', () async {
      await dbHelper.saveUserSettings(const UserSettings(
        negativeAppLimit: 30,
        neutralAppLimit: 120,
        productiveAppLimit: -1,
        gracePeriod: 5,
        snoozeEnabled: false,
        snoozeDuration: 5,
        usageLimitsEnabled: true,
      ));

      final startMs = refTodayStart + 1000;
      final endMs = startMs + (35 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      await interventionService.evaluatePackage(
        'com.example.app1',
        now: refNow,
      );

      final snoozed = await interventionService.snooze(now: refNow);

      expect(snoozed, isFalse);
      expect(interventionService.currentState!.isSnoozed, isFalse);
      expect(
        interventionService.getCurrentStatus(now: refNow),
        equals(InterventionStatus.gracePeriod),
      );
    });

    test('7. Snooze uses configured duration', () async {
      await dbHelper.saveUserSettings(const UserSettings(
        negativeAppLimit: 30,
        neutralAppLimit: 120,
        productiveAppLimit: -1,
        gracePeriod: 5,
        snoozeEnabled: true,
        snoozeDuration: 15,
        usageLimitsEnabled: true,
      ));

      final startMs = refTodayStart + 1000;
      final endMs = startMs + (35 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      await interventionService.evaluatePackage(
        'com.example.app1',
        now: refNow,
      );

      await interventionService.snooze(now: refNow);

      final state = interventionService.currentState!;
      expect(state.snoozeEndTime, equals(refNow.add(const Duration(minutes: 15))));
      expect(state.remainingSnoozeSeconds(refNow), equals(900));
    });

    test('8. Grace expiry returns to intervention-required state', () async {
      final startMs = refTodayStart + 1000;
      final endMs = startMs + (35 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      final state = await interventionService.evaluatePackage(
        'com.example.app1',
        now: refNow,
      );

      // At refNow + 5 minutes and 1 second (past 5m grace period)
      final expiredNow = refNow.add(const Duration(minutes: 5, seconds: 1));

      expect(
        state!.getStatusAt(expiredNow),
        equals(InterventionStatus.interventionRequired),
      );
      expect(
        interventionService.getCurrentStatus(now: expiredNow),
        equals(InterventionStatus.interventionRequired),
      );
    });

    test('9. Snooze expiry returns to intervention-required state', () async {
      final startMs = refTodayStart + 1000;
      final endMs = startMs + (35 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      await interventionService.evaluatePackage(
        'com.example.app1',
        now: refNow,
      );
      await interventionService.snooze(now: refNow);

      // At refNow + 5 minutes and 1 second (past 5m snooze period)
      final expiredNow = refNow.add(const Duration(minutes: 5, seconds: 1));

      expect(
        interventionService.currentState!.getStatusAt(expiredNow),
        equals(InterventionStatus.interventionRequired),
      );
      expect(
        interventionService.getCurrentStatus(now: expiredNow),
        equals(InterventionStatus.interventionRequired),
      );
    });

    test('10. Repeated monitoring events do not create duplicate interventions', () async {
      final startMs = refTodayStart + 1000;
      final endMs = startMs + (35 * 60 * 1000);
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: 'com.example.app1',
        startTime: startMs,
        endTime: endMs,
        duration: endMs - startMs,
      ));

      final initialGraceStart = refNow;
      final state1 = await interventionService.evaluatePackage(
        'com.example.app1',
        now: initialGraceStart,
      );

      // Subsequent monitoring event 30 seconds later
      final t1 = refNow.add(const Duration(seconds: 30));
      final state2 = await interventionService.evaluatePackage(
        'com.example.app1',
        now: t1,
      );

      // Subsequent monitoring event 2 minutes later
      final t2 = refNow.add(const Duration(minutes: 2));
      final state3 = await interventionService.evaluatePackage(
        'com.example.app1',
        now: t2,
      );

      expect(state1!.graceStartTime, equals(initialGraceStart));
      expect(state2!.graceStartTime, equals(initialGraceStart));
      expect(state3!.graceStartTime, equals(initialGraceStart));
      expect(
        state3.graceEndTime,
        equals(initialGraceStart.add(const Duration(minutes: 5))),
      );
    });
  });
}
