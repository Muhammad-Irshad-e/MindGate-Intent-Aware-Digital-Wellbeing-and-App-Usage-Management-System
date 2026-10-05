import 'package:flutter/services.dart';

class PermissionService {
  static const MethodChannel _channel = MethodChannel('com.mindgate/permissions');

  /// Check whether Usage Access (PACKAGE_USAGE_STATS) permission is granted
  Future<bool> checkUsageAccess() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('checkUsageAccess');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Open Android Usage Access Settings page
  Future<bool> openUsageAccessSettings() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('openUsageAccessSettings');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Check whether MindGate Accessibility Service is enabled
  Future<bool> checkAccessibilityService() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('checkAccessibilityService');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Open Android Accessibility Settings page
  Future<bool> openAccessibilitySettings() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('openAccessibilitySettings');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Check whether Notifications permission is granted
  Future<bool> checkNotificationPermission() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('checkNotificationPermission');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Request Notification permission or open App Notification Settings
  Future<bool> requestNotificationPermission() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}
