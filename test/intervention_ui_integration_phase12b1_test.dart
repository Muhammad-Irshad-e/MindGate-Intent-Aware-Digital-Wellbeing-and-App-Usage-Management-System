// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindgate/data/database/database_helper.dart';
import 'package:mindgate/data/models/app_category_model.dart';
import 'package:mindgate/data/models/app_usage_record.dart';
import 'package:mindgate/data/models/intervention_state_model.dart';
import 'package:mindgate/data/models/user_settings_model.dart';
import 'package:mindgate/presentation/screens/intervention_screen.dart';
import 'package:mindgate/services/intervention_service.dart';
import 'package:mindgate/services/usage_limit_service.dart';
import 'package:mindgate/services/usage_monitoring_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int get todayMidnightMs {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
}

/// Phase 12B-1 Integration Tests
///
/// Strategy:
/// - Unit tests (groups 1-5) verify the stream→state→action logic directly
///   against InterventionService/UsageMonitoringService with a real in-memory DB.
///   These avoid the DashboardScreen analytics SQLite hang in fake-async widget tests.
/// - Widget test (group 6) verifies the InterventionScreen widget itself renders
///   and responds correctly to onTakeBreak / onSnooze callbacks in isolation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // ── Shared DB/service setup ───────────────────────────────────────────────

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
    // Use customRawStream=Stream.empty() so no EventChannel is touched in tests
    service = UsageMonitoringService(
      dbHelper: dbHelper,
      interventionService: interventionService,
      customRawStream: const Stream.empty(),
    );
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  Future<void> seedUsageMs(String pkg, int durationMs) async {
    final start = todayMidnightMs + 1000;
    await dbHelper.insertUsageRecord(AppUsageRecord(
      packageName: pkg,
      startTime: start,
      endTime: start + durationMs,
      duration: durationMs,
    ));
  }

  Map<dynamic, dynamic> limitReachedEvent(String packageName) => {
        'eventType': 'limit_reached',
        'packageName': packageName,
        'startTime': DateTime.now().millisecondsSinceEpoch,
        'isLimitReached': true,
      };

  // ── a. Intervention state activates when limit is reached ─────────────────

  test('a. intervention state causes intervention state to activate', () async {
    await seedUsageMs('com.example.badapp', 35 * 60 * 1000); // 35 min > 30 min limit

    final emitted = <InterventionState>[];
    final sub = service.limitReachedStream.listen(emitted.add);
    addTearDown(sub.cancel);

    final state = await service.handleIncomingForegroundEvent(
        limitReachedEvent('com.example.badapp'));

    await Future<void>.delayed(Duration.zero);

    // Stream emitted and state is active
    expect(state, isNotNull);
    expect(emitted.length, equals(1));
    expect(emitted.first.packageName, equals('com.example.badapp'));
    expect(emitted.first.category, equals(AppCategoryType.negative));

    final status = state!.getStatusAt(DateTime.now());
    expect(
      status == InterventionStatus.gracePeriod ||
          status == InterventionStatus.interventionRequired,
      isTrue,
    );

    // interventionService has the active state
    expect(service.interventionService.currentState, isNotNull);
    expect(service.interventionService.currentState!.packageName,
        equals('com.example.badapp'));
  });

  // ── b. Take a Break clears the intervention ───────────────────────────────

  test('b. Take a Break clears the intervention state', () async {
    await seedUsageMs('com.example.badapp', 35 * 60 * 1000);

    await service.handleIncomingForegroundEvent(
        limitReachedEvent('com.example.badapp'));

    expect(service.interventionService.currentState, isNotNull);

    // Simulate Take a Break action
    service.interventionService.takeABreak();

    expect(service.interventionService.currentState, isNull);
  });

  // ── c. Snooze uses the configured duration ────────────────────────────────

  test('c. Snooze uses configured snoozeDuration from UserSettings', () async {
    // Configure 10-minute snooze
    await dbHelper.saveUserSettings(const UserSettings(
      settingId: 1,
      negativeAppLimit: 30,
      neutralAppLimit: 120,
      productiveAppLimit: -1,
      gracePeriod: 5,
      snoozeEnabled: true,
      snoozeDuration: 10,
      usageLimitsEnabled: true,
    ));

    await seedUsageMs('com.example.badapp', 35 * 60 * 1000);
    await service.handleIncomingForegroundEvent(
        limitReachedEvent('com.example.badapp'));

    expect(service.interventionService.currentState, isNotNull);

    final before = DateTime.now();
    final success = await service.interventionService.snooze();
    expect(success, isTrue);

    final activeState = service.interventionService.currentState;
    expect(activeState, isNotNull);
    expect(activeState!.isSnoozed, isTrue);
    expect(activeState.snoozeEndTime, isNotNull);

    // snooze end should be ~10 minutes from now
    final snoozeRemaining = activeState.remainingSnoozeSeconds(before);
    expect(snoozeRemaining, greaterThan(590));
    expect(snoozeRemaining, lessThanOrEqualTo(600));
  });

  // ── d. Disabled snooze does not activate snooze ───────────────────────────

  test('d. disabled snooze does not activate snooze', () async {
    await dbHelper.saveUserSettings(const UserSettings(
      settingId: 1,
      negativeAppLimit: 30,
      neutralAppLimit: 120,
      productiveAppLimit: -1,
      gracePeriod: 5,
      snoozeEnabled: false,
      snoozeDuration: 5,
      usageLimitsEnabled: true,
    ));

    await seedUsageMs('com.example.badapp', 35 * 60 * 1000);
    await service.handleIncomingForegroundEvent(
        limitReachedEvent('com.example.badapp'));

    expect(service.interventionService.currentState, isNotNull);

    final success = await service.interventionService.snooze();
    expect(success, isFalse);

    // State must still exist but NOT snoozed
    expect(service.interventionService.currentState, isNotNull);
    expect(service.interventionService.currentState!.isSnoozed, isFalse);
  });

  // ── e. Repeated events do not reset the grace timer ──────────────────────

  test('e. repeated limit-reached events do not reset the existing grace timer',
      () async {
    await seedUsageMs('com.example.badapp', 35 * 60 * 1000);

    // First event
    final s1 = await service.handleIncomingForegroundEvent(
        limitReachedEvent('com.example.badapp'));
    expect(s1, isNotNull);
    final graceStart = s1!.graceStartTime;
    final graceEnd = s1.graceEndTime;

    // Second event — must preserve existing timer
    final s2 = await service.handleIncomingForegroundEvent(
        limitReachedEvent('com.example.badapp'));
    expect(s2, isNotNull);
    expect(s2!.graceStartTime, equals(graceStart));
    expect(s2.graceEndTime, equals(graceEnd));
  });

  // ── Widget test: InterventionScreen renders & actions work in isolation ────

  group('InterventionScreen widget', () {
    testWidgets(
        '1. renders app name, category, used minutes, grace timer, and Take a Break button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InterventionScreen(
            appName: 'Bad App',
            categoryName: 'Negative',
            usedMinutes: 35,
            remainingSeconds: 299,
            snoozeEnabled: true,
            snoozeDuration: 5,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Usage Limit Reached'), findsOneWidget);
      expect(find.textContaining('Bad App'), findsOneWidget);
      expect(find.textContaining('(Negative)'), findsOneWidget);
      expect(find.textContaining('35 minutes'), findsOneWidget);
      expect(find.text('Take a Break'), findsOneWidget);
      expect(find.textContaining('Snooze'), findsOneWidget);

      // Cancel the periodic timer cleanly
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('2. snooze button hidden when snoozeEnabled=false',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InterventionScreen(
            appName: 'Bad App',
            usedMinutes: 35,
            remainingSeconds: 299,
            snoozeEnabled: false,
            snoozeDuration: 5,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Snooze'), findsNothing);
      expect(find.text('Take a Break'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('3. onTakeBreak callback is invoked when button tapped',
        (WidgetTester tester) async {
      bool tookBreak = false;

      await tester.pumpWidget(
        MaterialApp(
          home: InterventionScreen(
            appName: 'Bad App',
            usedMinutes: 35,
            remainingSeconds: 299,
            snoozeEnabled: true,
            snoozeDuration: 5,
            onTakeBreak: () => tookBreak = true,
            onSnooze: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Take a Break'));
      await tester.pump();

      expect(tookBreak, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('4. onSnooze callback is invoked when snooze button tapped',
        (WidgetTester tester) async {
      bool snoozeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: InterventionScreen(
            appName: 'Bad App',
            usedMinutes: 35,
            remainingSeconds: 299,
            snoozeEnabled: true,
            snoozeDuration: 5,
            onTakeBreak: () {},
            onSnooze: () => snoozeTapped = true,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.textContaining('Snooze'));
      await tester.pump();

      expect(snoozeTapped, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('5. grace period countdown displays initial remaining seconds',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InterventionScreen(
            appName: 'Test App',
            usedMinutes: 30,
            remainingSeconds: 180, // 3:00
            snoozeEnabled: false,
            snoozeDuration: 5,
          ),
        ),
      );
      await tester.pump();

      // Should display 03:00
      expect(find.text('03 : 00'), findsOneWidget);
      expect(find.text('(Grace Period)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
