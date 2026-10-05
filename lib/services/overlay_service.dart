import 'package:flutter/services.dart';

/// Service managing communication between Flutter and the Android system overlay layer.
///
/// Enables MindGate to display its native intervention overlay above the currently
/// active foreground application (such as Instagram) via [MethodChannel].
class OverlayService {
  static const MethodChannel _channel = MethodChannel('com.mindgate/overlay');

  final VoidCallback? onTakeBreak;
  final VoidCallback? onSnooze;

  OverlayService({
    this.onTakeBreak,
    this.onSnooze,
  }) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onTakeBreak':
        onTakeBreak?.call();
        break;
      case 'onSnooze':
        onSnooze?.call();
        break;
      default:
        break;
    }
  }

  /// Commands Android to display or update the intervention overlay.
  Future<bool> showOverlay({
    required String packageName,
    required String appName,
    required String categoryName,
    required int usedMinutes,
    required int remainingSeconds,
    required bool snoozeEnabled,
    required int snoozeDuration,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('showOverlay', {
        'packageName': packageName,
        'appName': appName,
        'categoryName': categoryName,
        'usedMinutes': usedMinutes,
        'remainingSeconds': remainingSeconds,
        'snoozeEnabled': snoozeEnabled,
        'snoozeDuration': snoozeDuration,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Commands Android to hide and remove the intervention overlay.
  Future<bool> hideOverlay() async {
    try {
      final result = await _channel.invokeMethod<bool>('hideOverlay');
      return result ?? false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if the native overlay is currently visible.
  Future<bool> isOverlayShowing() async {
    try {
      final result = await _channel.invokeMethod<bool>('isOverlayShowing');
      return result ?? false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
