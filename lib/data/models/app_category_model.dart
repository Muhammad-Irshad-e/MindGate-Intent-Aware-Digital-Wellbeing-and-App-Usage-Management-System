enum AppCategoryType {
  productive,
  neutral,
  negative,
}

class AppCategoryInfo {
  final String packageName;
  final String appName;
  final String iconAsset;
  final AppCategoryType category;

  const AppCategoryInfo({
    required this.packageName,
    required this.appName,
    required this.iconAsset,
    required this.category,
  });

  AppCategoryInfo copyWith({
    String? packageName,
    String? appName,
    String? iconAsset,
    AppCategoryType? category,
  }) {
    return AppCategoryInfo(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      iconAsset: iconAsset ?? this.iconAsset,
      category: category ?? this.category,
    );
  }

  /// Converts this model instance into a SQLite row Map.
  Map<String, dynamic> toDbMap() {
    return {
      'packageName': packageName,
      'appName': appName,
      'iconAsset': iconAsset,
      'category': category.name,
    };
  }

  /// Constructs an [AppCategoryInfo] from a SQLite row Map.
  factory AppCategoryInfo.fromDbMap(Map<String, dynamic> map) {
    final catName = map['category'] as String? ?? 'neutral';
    final type = AppCategoryType.values.firstWhere(
      (e) => e.name == catName,
      orElse: () => AppCategoryType.neutral,
    );

    return AppCategoryInfo(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      iconAsset: map['iconAsset'] as String? ?? '',
      category: type,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppCategoryInfo &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName &&
          appName == other.appName &&
          iconAsset == other.iconAsset &&
          category == other.category;

  @override
  int get hashCode =>
      packageName.hashCode ^
      appName.hashCode ^
      iconAsset.hashCode ^
      category.hashCode;
}
