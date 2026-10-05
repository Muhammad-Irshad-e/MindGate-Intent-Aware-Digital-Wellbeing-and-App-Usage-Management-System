/// System package filtering utility for MindGate analytics.
///
/// Filters out Android system components, OEM launchers, keyboard input methods,
/// and OS system UI packages from user-facing usage analytics (such as Today's Usage
/// and Dashboard top apps).
///
/// Note: System packages are ONLY excluded from analytics/usage reports.
/// They are NOT removed from App Categories or Android app discovery.
class SystemPackages {
  static const Set<String> _knownSystemPackages = {
    'android',
    'com.android.systemui',
    'com.android.launcher',
    'com.android.launcher2',
    'com.android.launcher3',
    'com.sec.android.app.launcher',
    'com.samsung.android.honeyboard',
    'com.google.android.apps.nexuslauncher',
    'com.google.android.inputmethod.latin',
    'com.touchtype.swiftkey',
    'com.miui.home',
    'com.oppo.launcher',
    'com.huawei.android.launcher',
    'com.google.android.permissioncontroller',
    'com.android.permissioncontroller',
    'com.android.packageinstaller',
  };

  /// Returns true if [packageName] belongs to a system UI, launcher, or input component.
  static bool isSystemPackage(String packageName) {
    final pkg = packageName.trim().toLowerCase();
    if (pkg.isEmpty) return true;
    if (_knownSystemPackages.contains(pkg)) return true;
    if (pkg.startsWith('com.android.launcher') ||
        pkg.startsWith('com.sec.android.app.launcher') ||
        pkg.startsWith('com.google.android.apps.nexuslauncher')) {
      return true;
    }
    return false;
  }
}
