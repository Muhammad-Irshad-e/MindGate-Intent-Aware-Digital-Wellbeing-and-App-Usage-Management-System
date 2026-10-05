import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
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

  group('Active Session Limit Evaluation Focused Tests (Phase 12B-2 Fix)', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late UsageLimitService limitService;
    late InterventionService interventionService;
    late UsageMonitoringService monitoringService;

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

      // Default settings: negative limit 1m (60,000 ms), neutral 120m, productive -1, grace 5m
      await dbHelper.saveUserSettings(const UserSettings(
        settingId: 1,
        negativeAppLimit: 1,
        neutralAppLimit: 120,
        productiveAppLimit: -1,
        gracePeriod: 5,
        snoozeEnabled: true,
        snoozeDuration: 5,
        usageLimitsEnabled: true,
      ));

      // Register Instagram as Negative app
      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.instagram.android',
        appName: 'Instagram',
        iconAsset: 'com.instagram.android',
        category: AppCategoryType.negative,
      ));

      // Register Google Docs as Productive app
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

    test('1. Active session below limit -> no intervention', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final sessionStart = nowMs - 10000; // 10 seconds active (< 1 min limit)

      final state = await monitoringService.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'com.instagram.android',
        'startTime': sessionStart,
      });

      expect(state, isNull);
      expect(interventionService.currentState, isNull);
      expect(monitoringService.isTimerActive, isTrue);
    });

    test('2. Active session crossing limit -> intervention triggered', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // Session started 70 seconds ago (70s > 60s limit of 1 min)
      final sessionStart = nowMs - 70000;

      InterventionState? emittedState;
      final sub = monitoringService.limitReachedStream.listen((s) {
        emittedState = s;
      });

      final state = await monitoringService.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'com.instagram.android',
        'startTime': sessionStart,
      });

      expect(state, isNotNull);
      expect(state!.packageName, equals('com.instagram.android'));
      expect(state.category, equals(AppCategoryType.negative));
      expect(interventionService.currentState, equals(state));

      await Future.delayed(Duration.zero);
      expect(emittedState, equals(state));

      await sub.cancel();
    });

    test('3. Repeated timer evaluations -> no duplicate intervention created', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final sessionStart = nowMs - 70000; // 70 seconds (> 60s limit)

      // First evaluation
      final s1 = await monitoringService.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'com.instagram.android',
        'startTime': sessionStart,
      });

      // Second periodic timer evaluation
      final s2 = await monitoringService.evaluateActiveSessionLimit(
        'com.instagram.android',
        sessionStart,
      );

      expect(s1, isNotNull);
      expect(s2, isNotNull);
      expect(s1!.graceStartTime, equals(s2!.graceStartTime)); // Same intervention state, no duplicate
      expect(interventionService.currentState, equals(s1));
    });

    test('4. Timer stops when active session ends (System UI / Launcher)', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // User opens Instagram
      await monitoringService.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'com.instagram.android',
        'startTime': nowMs,
      });

      expect(monitoringService.isTimerActive, isTrue);
      expect(monitoringService.activePackageName, equals('com.instagram.android'));

      // User switches to Launcher / System UI
      await monitoringService.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'com.sec.android.app.launcher',
      });

      expect(monitoringService.isTimerActive, isFalse);
      expect(monitoringService.activePackageName, isNull);
    });

    test('5. Timer restarts for a new active session', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Session 1: Instagram
      await monitoringService.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'com.instagram.android',
        'startTime': nowMs,
      });
      expect(monitoringService.activePackageName, equals('com.instagram.android'));
      expect(monitoringService.isTimerActive, isTrue);

      // Session 2: YouTube (switch app)
      await monitoringService.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'com.google.android.youtube',
        'startTime': nowMs + 1000,
      });
      expect(monitoringService.activePackageName, equals('com.google.android.youtube'));
      expect(monitoringService.isTimerActive, isTrue);
    });

    test('6. Unlimited productive app -> no intervention', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final sessionStart = nowMs - (120 * 60 * 1000); // 120 minutes active

      final state = await monitoringService.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'com.google.android.apps.docs',
        'startTime': sessionStart,
      });

      expect(state, isNull);
      expect(interventionService.currentState, isNull);

      final timerEval = await monitoringService.evaluateActiveSessionLimit(
        'com.google.android.apps.docs',
        sessionStart,
      );
      expect(timerEval, isNull);
    });
  });
}
