import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/data/models/intervention_state_model.dart';
import 'package:mindgate/data/models/user_settings_model.dart';
import 'package:mindgate/services/intervention_service.dart';
import 'package:mindgate/services/usage_limit_service.dart';
import 'package:mindgate/services/usage_monitoring_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Phase 12B-2 Intervention Enforcement Focused Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late UsageLimitService limitService;
    late InterventionService interventionService;
    late UsageMonitoringService monitoringService;

    final refNow = DateTime(2026, 10, 3, 10, 0, 0);
    final refTodayStart = DateTime(2026, 10, 3, 0, 0, 0).millisecondsSinceEpoch;

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
      monitoringService = UsageMonitoringService(
        dbHelper: dbHelper,
        interventionService: interventionService,
        customRawStream: const Stream.empty(),
      );

      // Default settings: negative limit 30m, grace 5m, snooze 5m
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

      // Category setup
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'com.instagram.android',
        category: AppCategoryType.negative,
      ));

      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.google.android.apps.docs',
        appName: 'Google Docs',
        iconAsset: 'com.google.android.apps.docs',
        category: AppCategoryType.productive,
      ));
    });

    tearDown(() async {
      monitoringService.dispose();
      await db.close();
    });

    Future<void> addUsageMinutes(String pkg, int minutes) async {
      final start = refTodayStart + 1000;
      final duration = minutes * 60 * 1000;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: pkg,
        startTime: start,
        endTime: start + duration,
        duration: duration,
      ));
    }

    test('1. Grace period starts once when limit is reached', () async {
      await addUsageMinutes('com.instagram.android', 35); // 35 min > 30 min limit

      final state = await interventionService.evaluatePackage(
        'com.instagram.android',
        now: refNow,
      );

      expect(state, isNotNull);
      expect(state!.graceStartTime, equals(refNow));
      expect(state.graceEndTime, equals(refNow.add(const Duration(minutes: 5))));
      expect(state.getStatusAt(refNow), equals(InterventionStatus.gracePeriod));
    });

    test('2. Grace period countdown & expiry state', () async {
      await addUsageMinutes('com.instagram.android', 35);
      final state = await interventionService.evaluatePackage(
        'com.instagram.android',
        now: refNow,
      );

      // 2 minutes in -> 180 seconds remaining
      final tMid = refNow.add(const Duration(minutes: 2));
      expect(state!.remainingGraceSeconds(tMid), equals(180));
      expect(state.getStatusAt(tMid), equals(InterventionStatus.gracePeriod));

      // Past 5 minutes -> status is interventionRequired with 0 remaining seconds
      final tExpired = refNow.add(const Duration(minutes: 5, seconds: 1));
      expect(state.remainingGraceSeconds(tExpired), equals(0));
      expect(state.getStatusAt(tExpired), equals(InterventionStatus.interventionRequired));
    });

    test('3. Snooze starts once and grants snooze period', () async {
      await addUsageMinutes('com.instagram.android', 35);
      await interventionService.evaluatePackage(
        'com.instagram.android',
        now: refNow,
      );

      final snoozed = await interventionService.snooze(now: refNow);
      expect(snoozed, isTrue);

      final currentState = interventionService.currentState!;
      expect(currentState.isSnoozed, isTrue);
      expect(currentState.getStatusAt(refNow), equals(InterventionStatus.snoozed));
      expect(currentState.snoozeEndTime, equals(refNow.add(const Duration(minutes: 5))));
    });

    test('4. Snooze expiry returns to interventionRequired state', () async {
      await addUsageMinutes('com.instagram.android', 35);
      await interventionService.evaluatePackage(
        'com.instagram.android',
        now: refNow,
      );
      await interventionService.snooze(now: refNow);

      final tSnoozeExpired = refNow.add(const Duration(minutes: 5, seconds: 1));
      expect(
        interventionService.currentState!.getStatusAt(tSnoozeExpired),
        equals(InterventionStatus.interventionRequired),
      );
    });

    test('5. Take a Break clears intervention state', () async {
      await addUsageMinutes('com.instagram.android', 35);
      await interventionService.evaluatePackage(
        'com.instagram.android',
        now: refNow,
      );

      expect(interventionService.currentState, isNotNull);
      interventionService.takeABreak();

      expect(interventionService.currentState, isNull);
      expect(interventionService.getCurrentStatus(now: refNow), equals(InterventionStatus.none));
    });

    test('6. Duplicate limit events do not create duplicate interventions', () async {
      await addUsageMinutes('com.instagram.android', 35);

      final s1 = await interventionService.evaluatePackage(
        'com.instagram.android',
        now: refNow,
      );
      final s2 = await interventionService.evaluatePackage(
        'com.instagram.android',
        now: refNow.add(const Duration(seconds: 45)),
      );

      expect(s1, equals(s2));
      expect(s2!.graceStartTime, equals(refNow));
    });

    test('7. Unlimited productive apps are not blocked', () async {
      await addUsageMinutes('com.google.android.apps.docs', 120);

      final state = await interventionService.evaluatePackage(
        'com.google.android.apps.docs',
        now: refNow,
      );

      expect(state, isNull);
      expect(interventionService.currentState, isNull);
    });

    test('8. Restricted app becomes enforced after grace expiry', () async {
      await addUsageMinutes('com.instagram.android', 35);
      await interventionService.evaluatePackage(
        'com.instagram.android',
        now: refNow,
      );

      final tExpired = refNow.add(const Duration(minutes: 5, seconds: 1));
      final status = interventionService.getCurrentStatus(now: tExpired);

      expect(status, equals(InterventionStatus.interventionRequired));
    });

    test('9. Re-entry after grace expiry does not grant a new grace period', () async {
      await addUsageMinutes('com.instagram.android', 35);
      
      // Initial evaluation starts 5-min grace period
      await interventionService.evaluatePackage(
        'com.instagram.android',
        now: refNow,
      );

      // User leaves app / takes break at t = 6 min (after grace period expired)
      final tReentry = refNow.add(const Duration(minutes: 6));
      
      // User re-opens Instagram while limit is still reached
      final stateReentry = await interventionService.evaluatePackage(
        'com.instagram.android',
        now: tReentry,
      );

      expect(stateReentry, isNotNull);
      // Status must be interventionRequired immediately (0 remaining grace seconds), NOT gracePeriod!
      expect(stateReentry!.getStatusAt(tReentry), equals(InterventionStatus.interventionRequired));
      expect(stateReentry.remainingGraceSeconds(tReentry), equals(0));
    });
  });
}
