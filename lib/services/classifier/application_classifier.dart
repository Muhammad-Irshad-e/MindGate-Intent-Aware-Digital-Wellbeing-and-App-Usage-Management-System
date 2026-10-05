import '../../data/models/app_category_model.dart';
import '../../data/models/app_info.dart';

/// Abstract contract for classifying applications into approved MindGate categories:
/// [AppCategoryType.productive], [AppCategoryType.neutral], or [AppCategoryType.negative].
abstract class ApplicationClassifier {
  /// Classifies an application based on available [AppInfo] metadata.
  AppCategoryType classify(AppInfo appInfo);
}

/// Lightweight, deterministic, local rule-based implementation of [ApplicationClassifier].
///
/// Uses package name and app title metadata pattern analysis to assign categories safely,
/// falling back conservatively to [AppCategoryType.neutral] for unrecognized or ambiguous apps.
class HeuristicApplicationClassifier implements ApplicationClassifier {
  const HeuristicApplicationClassifier();

  static const Map<String, AppCategoryType> _exactPackageMap = {
    // Negative / Distracting Apps
    'com.google.android.youtube': AppCategoryType.negative,
    'com.instagram.android': AppCategoryType.negative,
    'com.facebook.katana': AppCategoryType.negative,
    'com.twitter.android': AppCategoryType.negative,
    'com.zhiliaoapp.musically': AppCategoryType.negative, // TikTok
    'com.ss.android.ugc.trill': AppCategoryType.negative, // TikTok alternate
    'com.snapchat.android': AppCategoryType.negative,
    'com.reddit.frontpage': AppCategoryType.negative,
    'com.pinterest': AppCategoryType.negative,
    'com.netflix.mediaclient': AppCategoryType.negative,
    'tv.twitch.android.app': AppCategoryType.negative,

    // Productive Apps
    'com.microsoft.vscode': AppCategoryType.productive,
    'so.notion.app': AppCategoryType.productive,
    'com.google.android.gm': AppCategoryType.productive,
    'com.google.android.apps.docs': AppCategoryType.productive,
    'com.google.android.apps.docs.editors.sheets': AppCategoryType.productive,
    'com.google.android.apps.docs.editors.slides': AppCategoryType.productive,
    'com.github.android': AppCategoryType.productive,
    'com.duolingo': AppCategoryType.productive,
    'md.obsidian': AppCategoryType.productive,
    'com.slack': AppCategoryType.productive,

    // Neutral Apps
    'com.whatsapp': AppCategoryType.neutral,
    'com.android.chrome': AppCategoryType.neutral,
    'com.spotify.music': AppCategoryType.neutral,
  };

  static const List<String> _negativeKeywords = [
    'youtube',
    'instagram',
    'facebook',
    'tiktok',
    'snapchat',
    'reddit',
    'pinterest',
    'netflix',
    'twitch',
    'hulu',
    'disney',
    'primevideo',
    'game',
    'games',
    'casino',
    'poker',
    'reels',
    'shorts',
  ];

  static const List<String> _productiveKeywords = [
    'vscode',
    'notion',
    'obsidian',
    'github',
    'gitlab',
    'duolingo',
    'coursera',
    'udemy',
    'stack overflow',
    'editor',
    'docs',
    'sheets',
    'slides',
    'office',
    'terminal',
    'compiler',
    'ide',
    'study',
  ];

  @override
  AppCategoryType classify(AppInfo appInfo) {
    final pkg = appInfo.packageName.trim().toLowerCase();
    final name = appInfo.appName.trim().toLowerCase();

    // Step 7: Invalid or empty app metadata defaults to Neutral
    if (pkg.isEmpty && name.isEmpty) {
      return AppCategoryType.neutral;
    }

    // 1. Check exact high-confidence package mappings
    if (_exactPackageMap.containsKey(pkg)) {
      return _exactPackageMap[pkg]!;
    }

    // 2. Check for known productive keywords in package or name
    for (final kw in _productiveKeywords) {
      if (pkg.contains(kw) || name.contains(kw)) {
        return AppCategoryType.productive;
      }
    }

    // 3. Check for known negative keywords in package or name
    for (final kw in _negativeKeywords) {
      if (pkg.contains(kw) || name.contains(kw)) {
        return AppCategoryType.negative;
      }
    }

    // Step 7: Conservative fallback for unclassified/unknown applications
    return AppCategoryType.neutral;
  }
}
