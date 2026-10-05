class UserSettings {
  final int settingId;
  final int negativeAppLimit;
  final int neutralAppLimit;
  final int productiveAppLimit; // -1 for no limit / unrestricted
  final int gracePeriod; // in minutes
  final bool snoozeEnabled;
  final int snoozeDuration; // in minutes
  final bool usageLimitsEnabled;

  const UserSettings({
    this.settingId = 1,
    required this.negativeAppLimit,
    required this.neutralAppLimit,
    required this.productiveAppLimit,
    required this.gracePeriod,
    required this.snoozeEnabled,
    this.snoozeDuration = 5,
    required this.usageLimitsEnabled,
  });

  UserSettings copyWith({
    int? settingId,
    int? negativeAppLimit,
    int? neutralAppLimit,
    int? productiveAppLimit,
    int? gracePeriod,
    bool? snoozeEnabled,
    int? snoozeDuration,
    bool? usageLimitsEnabled,
  }) {
    return UserSettings(
      settingId: settingId ?? this.settingId,
      negativeAppLimit: negativeAppLimit ?? this.negativeAppLimit,
      neutralAppLimit: neutralAppLimit ?? this.neutralAppLimit,
      productiveAppLimit: productiveAppLimit ?? this.productiveAppLimit,
      gracePeriod: gracePeriod ?? this.gracePeriod,
      snoozeEnabled: snoozeEnabled ?? this.snoozeEnabled,
      snoozeDuration: snoozeDuration ?? this.snoozeDuration,
      usageLimitsEnabled: usageLimitsEnabled ?? this.usageLimitsEnabled,
    );
  }

  /// Serializes [UserSettings] to SQLite row map.
  Map<String, dynamic> toDbMap() {
    return {
      'settingId': settingId,
      'negativeAppLimit': negativeAppLimit,
      'neutralAppLimit': neutralAppLimit,
      'productiveAppLimit': productiveAppLimit,
      'gracePeriod': gracePeriod,
      'snoozeEnabled': snoozeEnabled ? 1 : 0,
      'snoozeDuration': snoozeDuration,
      'usageLimitsEnabled': usageLimitsEnabled ? 1 : 0,
    };
  }

  /// Constructs [UserSettings] from SQLite row map.
  factory UserSettings.fromDbMap(Map<String, dynamic> map) {
    return UserSettings(
      settingId: map['settingId'] as int? ?? 1,
      negativeAppLimit: map['negativeAppLimit'] as int? ?? 30,
      neutralAppLimit: map['neutralAppLimit'] as int? ?? 120,
      productiveAppLimit: map['productiveAppLimit'] as int? ?? -1,
      gracePeriod: map['gracePeriod'] as int? ?? 5,
      snoozeEnabled: (map['snoozeEnabled'] as int? ?? 1) == 1,
      snoozeDuration: map['snoozeDuration'] as int? ?? 5,
      usageLimitsEnabled: (map['usageLimitsEnabled'] as int? ?? 1) == 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSettings &&
          runtimeType == other.runtimeType &&
          settingId == other.settingId &&
          negativeAppLimit == other.negativeAppLimit &&
          neutralAppLimit == other.neutralAppLimit &&
          productiveAppLimit == other.productiveAppLimit &&
          gracePeriod == other.gracePeriod &&
          snoozeEnabled == other.snoozeEnabled &&
          snoozeDuration == other.snoozeDuration &&
          usageLimitsEnabled == other.usageLimitsEnabled;

  @override
  int get hashCode =>
      settingId.hashCode ^
      negativeAppLimit.hashCode ^
      neutralAppLimit.hashCode ^
      productiveAppLimit.hashCode ^
      gracePeriod.hashCode ^
      snoozeEnabled.hashCode ^
      snoozeDuration.hashCode ^
      usageLimitsEnabled.hashCode;
}
