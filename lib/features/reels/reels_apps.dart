/// An app the reels counter knows how to watch.
class ReelsApp {
  const ReelsApp({
    required this.packageName,
    required this.name,
    required this.surface,
    this.beta = false,
  });

  final String packageName;
  final String name;

  /// What the app calls its short-video player ("Reels", "Shorts", …).
  final String surface;

  /// Detection not yet verified on a device; counts may be off.
  final bool beta;
}

/// Supported apps, in display order. Keep the package names in sync with the
/// `<queries>` block in android/app/src/main/AndroidManifest.xml.
///
/// Facebook Lite is deliberately absent: it exposes no view ids, so its feed
/// and its reels look identical to the counter.
const reelsApps = <ReelsApp>[
  ReelsApp(
    packageName: 'com.google.android.youtube',
    name: 'YouTube',
    surface: 'Shorts',
  ),
  ReelsApp(
    packageName: 'com.instagram.android',
    name: 'Instagram',
    surface: 'Reels',
  ),
  ReelsApp(
    packageName: 'com.facebook.katana',
    name: 'Facebook',
    surface: 'Reels',
    beta: true,
  ),
  ReelsApp(
    packageName: 'com.instagram.lite',
    name: 'Instagram Lite',
    surface: 'Reels',
    beta: true,
  ),
  ReelsApp(
    packageName: 'com.snapchat.android',
    name: 'Snapchat',
    surface: 'Spotlight',
    beta: true,
  ),
  ReelsApp(
    packageName: 'in.mohalla.video',
    name: 'Moj',
    surface: 'Videos',
    beta: true,
  ),
  ReelsApp(
    packageName: 'com.eterno.shortvideos',
    name: 'Josh',
    surface: 'Videos',
    beta: true,
  ),
  ReelsApp(
    packageName: 'in.mohalla.sharechat',
    name: 'ShareChat',
    surface: 'Videos',
    beta: true,
  ),
];

ReelsApp? reelsAppFor(String packageName) {
  for (final app in reelsApps) {
    if (app.packageName == packageName) return app;
  }
  return null;
}
