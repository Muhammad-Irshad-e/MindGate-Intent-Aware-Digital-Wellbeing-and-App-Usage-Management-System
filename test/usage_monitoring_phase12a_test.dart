// ignore_for_file: lines_longer_than_80_chars

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

DateTime get now => DateTime.now();
int get todayMidnightMs {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Phase 12A: handleIncomingForegroundEvent integration tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late UsageLimitService limitService;
    late InterventionService interventionService;
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

      await dbHelper.insertOrUpdateAppCategory(const AppCategoryInfo(
        packageName: 'com.example.badapp',
        appName: 'Bad App',
        iconAsset: 'com.example.badapp',
        category: AppCategoryType.negative,
      ));

      limitService = UsageLimitService(dbHelper: dbHelper);
      interventionService = InterventionService(
        limitService: limitService,
        dbHelper: dbHelper,
      );

      service = UsageMonitoringService(
        dbHelper: dbHelper,
        interventionService: interventionService,
      );
    });

    tearDown(() async {
      service.dispose();
      await db.close();
    });

    // Build a foreground_changed or limit_reached event map
    Map<dynamic, dynamic> foregroundEvent({
      required String packageName,
      bool isLimitReached = false,
    }) =>
        {
          'eventType': isLimitReached ? 'limit_reached' : 'foreground_changed',
          'packageName': packageName,
          'startTime': DateTime.now().millisecondsSinceEpoch,
          'isLimitReached': isLimitReached,
          'category': 'negative',
          'usageMs': 0,
          'limitMinutes': 30,
        };

    // Insert a completed usage record starting from todayMidnight + offsetMs
    Future<void> seedUsageMs(
        String pkg, int durationMs, int startOffset) async {
      final start = todayMidnightMs + startOffset;
      await dbHelper.insertUsageRecord(AppUsageRecord(
        packageName: pkg,
        startTime: start,
        endTime: start + durationMs,
        duration: durationMs,
      ));
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    test('1. Limit not reached returns null', () async {
      // 10 min seeded, limit is 30 — should not trigger
      await seedUsageMs('com.example.badapp', 10 * 60 * 1000, 1000);
      final state = await service.handleIncomingForegroundEvent(
          foregroundEvent(packageName: 'com.example.badapp'));
      expect(state, isNull);
    });

    test('2. Limit reached returns InterventionState in grace period', () async {
      // 35 min seeded, limit is 30
      await seedUsageMs('com.example.badapp', 35 * 60 * 1000, 1000);
      final state = await service.handleIncomingForegroundEvent(foregroundEvent(
        packageName: 'com.example.badapp',
        isLimitReached: true,
      ));
      expect(state, isNotNull);
      expect(state!.packageName, equals('com.example.badapp'));
      expect(state.category, equals(AppCategoryType.negative));
      expect(state.getStatusAt(now), equals(InterventionStatus.gracePeriod));
    });

    test('3. Repeated limit-reached events do not reset grace timer', () async {
      await seedUsageMs('com.example.badapp', 35 * 60 * 1000, 1000);
      final s1 = await service.handleIncomingForegroundEvent(foregroundEvent(
        packageName: 'com.example.badapp',
        isLimitReached: true,
      ));
      final graceStart = s1!.graceStartTime;

      // Second call immediately after — grace timer must not reset
      final s2 = await service.handleIncomingForegroundEvent(foregroundEvent(
        packageName: 'com.example.badapp',
        isLimitReached: true,
      ));
      expect(s2!.graceStartTime, equals(graceStart));
    });

    test('4. System package "android" is ignored', () async {
      final state = await service.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'android',
        'startTime': DateTime.now().millisecondsSinceEpoch,
        'isLimitReached': false,
      });
      expect(state, isNull);
      expect(service.interventionService.currentState, isNull);
    });

    test('5. Launcher package com.android.launcher3 is ignored', () async {
      final state = await service.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': 'com.android.launcher3',
        'startTime': DateTime.now().millisecondsSinceEpoch,
        'isLimitReached': false,
      });
      expect(state, isNull);
      expect(service.interventionService.currentState, isNull);
    });

    test('6. Empty packageName is ignored safely', () async {
      final state = await service.handleIncomingForegroundEvent({
        'eventType': 'foreground_changed',
        'packageName': '',
        'startTime': DateTime.now().millisecondsSinceEpoch,
      });
      expect(state, isNull);
    });

    test(
        '7. Completed session map (duration>0, no eventType) is ignored',
        () async {
      final state = await service.handleIncomingForegroundEvent({
        'packageName': 'com.example.badapp',
        'startTime': 1000,
        'endTime': 61000,
        'duration': 60000,
      });
      expect(state, isNull);
    });

    test('8. limitReachedStream emits when limit reached', () async {
      await seedUsageMs('com.example.badapp', 35 * 60 * 1000, 1000);
      final emitted = <InterventionState>[];
      final sub = service.limitReachedStream.listen(emitted.add);
      addTearDown(sub.cancel);

      await service.handleIncomingForegroundEvent(foregroundEvent(
        packageName: 'com.example.badapp',
        isLimitReached: true,
      ));

      // Allow microtasks to drain
      await Future<void>.delayed(Duration.zero);

      expect(emitted.length, equals(1));
      expect(emitted.first.packageName, equals('com.example.badapp'));
    });

    test('9. limitReachedStream does not emit when limit not reached', () async {
      await seedUsageMs('com.example.badapp', 10 * 60 * 1000, 1000);
      final emitted = <InterventionState>[];
      final sub = service.limitReachedStream.listen(emitted.add);
      addTearDown(sub.cancel);

      await service.handleIncomingForegroundEvent(
          foregroundEvent(packageName: 'com.example.badapp'));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);
    });

    test('10. Snooze state is preserved on subsequent foreground events',
        () async {
      await seedUsageMs('com.example.badapp', 35 * 60 * 1000, 1000);

      // Trigger initial intervention
      await service.handleIncomingForegroundEvent(foregroundEvent(
        packageName: 'com.example.badapp',
        isLimitReached: true,
      ));

      // User snoozes — uses real time so snooze window is in the future
      final snoozed = await interventionService.snooze();
      expect(snoozed, isTrue);
      expect(interventionService.currentState!.isSnoozed, isTrue);
      final snoozeEnd = interventionService.currentState!.snoozeEndTime;

      // Second foreground event — snooze must be preserved (re-trigger protection)
      await service.handleIncomingForegroundEvent(foregroundEvent(
        packageName: 'com.example.badapp',
        isLimitReached: true,
      ));
      expect(interventionService.currentState!.isSnoozed, isTrue);
      expect(
          interventionService.currentState!.snoozeEndTime, equals(snoozeEnd));
    });

    test('11. dispose() does not throw when streams are active', () async {
      service.sessionStream;
      service.limitReachedStream;
      expect(() => service.dispose(), returnsNormally);
    });
  });
}
