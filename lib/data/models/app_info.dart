/// Represents information about an installed application on the device.
///
/// Contains basic app identity attributes required for MindGate's category
/// management without accessing sensitive personal content or data.
class AppInfo {
  /// Unique Android package identifier (e.g. "com.google.android.youtube").
  final String packageName;

  /// User-visible application name (e.g. "YouTube").
  final String appName;

  const AppInfo({
    required this.packageName,
    required this.appName,
  });

  /// Factory constructor to safely construct [AppInfo] from platform map.
  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppInfo(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
    );
  }

  /// Converts instance to Map representation.
  Map<String, String> toMap() => {
        'packageName': packageName,
        'appName': appName,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppInfo &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName &&
          appName == other.appName;

  @override
  int get hashCode => packageName.hashCode ^ appName.hashCode;

  @override
  String toString() => 'AppInfo(appName: $appName, packageName: $packageName)';
}
