import 'dart:async';
import '../data/database/database_helper.dart';
import '../data/models/intervention_state_model.dart';
import '../data/models/usage_limit_model.dart';
import 'usage_limit_service.dart';

/// Intervention state management service.
///
/// Features Phase 12B-2 integration:
/// 1. Connects existing [UsageLimitService] limit detection to in-memory intervention state.
/// 2. Manages Grace Period lifecycle (defaults to 5 minutes from [UserSettings]).
/// 3. Manages Snooze lifecycle (duration and toggle from [UserSettings]).
/// 4. Enforces re-trigger & re-entry protection: prevents duplicate interventions when monitoring events repeat
///    and prevents re-granting an expired grace period when a restricted app is re-opened.
class InterventionService {
  final UsageLimitService _limitService;
  final DatabaseHelper _dbHelper;

  InterventionState? _currentState;
  final Map<String, InterventionState> _stateHistory = {};
  Timer? _snoozeTimer;

  /// Optional callback triggered when snooze period expires while service is active.
  void Function(InterventionState expiredState)? onSnoozeExpired;

  InterventionService({
    UsageLimitService? limitService,
    DatabaseHelper? dbHelper,
    this.onSnoozeExpired,
  })  : _limitService = limitService ?? UsageLimitService(dbHelper: dbHelper),
        _dbHelper = dbHelper ?? DatabaseHelper();

  /// Gets the currently active [InterventionState], if any.
  InterventionState? get currentState => _currentState;

  /// Associated [DatabaseHelper] instance.
  DatabaseHelper get dbHelper => _dbHelper;

  /// Retrieves current [InterventionStatus] evaluated at [now].
  InterventionStatus getCurrentStatus({DateTime? now}) {
    if (_currentState == null) return InterventionStatus.none;
    return _currentState!.getStatusAt(now ?? DateTime.now());
  }

  /// Evaluates limit status for [packageName] and updates intervention state accordingly.
  ///
  /// Re-trigger & Re-entry Protection:
  /// - If state is currently in grace period or snoozed, returns existing state without resetting timers.
  /// - If grace period or snooze has expired, returns the expired state (`interventionRequired`)
  ///   so re-entry immediately enforces the restriction without granting a new grace period.
  Future<InterventionState?> evaluatePackage(
    String packageName, {
    DateTime? now,
    int? currentSessionStartTime,
  }) async {
    final refNow = now ?? DateTime.now();

    // 1. Evaluate limit status using existing UsageLimitService
    final limitResult = await _limitService.checkLimitForPackage(
      packageName,
      now: refNow,
      currentSessionStartTime: currentSessionStartTime,
    );

    // 2. Limit not reached: clear active state and history if matching packageName
    if (limitResult.status == LimitStatus.notLimited) {
      _stateHistory.remove(packageName);
      if (_currentState != null && _currentState!.packageName == packageName) {
        _currentState = null;
      }
      return null;
    }

    // 3. Re-trigger & Re-entry protection check
    final existingState = (_currentState != null && _currentState!.packageName == packageName)
        ? _currentState
        : _stateHistory[packageName];

    if (existingState != null) {
      final activeStatus = existingState.getStatusAt(refNow);

      if (activeStatus == InterventionStatus.gracePeriod ||
          activeStatus == InterventionStatus.snoozed ||
          activeStatus == InterventionStatus.interventionRequired) {
        _currentState = existingState;
        _stateHistory[packageName] = existingState;
        return _currentState;
      }
    }

    // 4. First time limit reached for this package: Fetch UserSettings to retrieve grace period
    final settings = await _dbHelper.getUserSettings();
    final graceMinutes = settings.gracePeriod > 0 ? settings.gracePeriod : 5;

    final newState = InterventionState(
      packageName: packageName,
      category: limitResult.category,
      graceStartTime: refNow,
      graceEndTime: refNow.add(Duration(minutes: graceMinutes)),
      usedMinutes: limitResult.todayCategoryUsageMinutes,
    );

    _currentState = newState;
    _stateHistory[packageName] = newState;
    return _currentState;
  }

  /// Clears active intervention state (Take a Break action).
  void takeABreak() {
    _snoozeTimer?.cancel();
    _snoozeTimer = null;
    _currentState = null;
  }

  /// Starts snooze period if snooze is enabled in [UserSettings].
  ///
  /// Returns `true` if snooze started successfully, or `false` if snooze is disabled/no active state.
  Future<bool> snooze({DateTime? now}) async {
    if (_currentState == null) return false;

    final refNow = now ?? DateTime.now();
    final settings = await _dbHelper.getUserSettings();

    if (!settings.snoozeEnabled) {
      return false;
    }

    final snoozeMinutes =
        settings.snoozeDuration > 0 ? settings.snoozeDuration : 5;

    final updatedState = _currentState!.copyWith(
      isSnoozed: true,
      snoozeStartTime: refNow,
      snoozeEndTime: refNow.add(Duration(minutes: snoozeMinutes)),
    );

    _currentState = updatedState;
    _stateHistory[updatedState.packageName] = updatedState;

    // Set up timer for snooze expiration notice if in live environment
    _snoozeTimer?.cancel();
    _snoozeTimer = Timer(Duration(minutes: snoozeMinutes), () {
      if (_currentState != null && _currentState!.packageName == updatedState.packageName) {
        onSnoozeExpired?.call(_currentState!);
      }
    });

    return true;
  }

  /// Releases resources.
  void dispose() {
    _snoozeTimer?.cancel();
    _snoozeTimer = null;
  }
}
