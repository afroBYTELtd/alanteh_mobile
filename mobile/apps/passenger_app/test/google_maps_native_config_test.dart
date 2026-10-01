import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The Maps keys live in git-ignored files (android/local.properties and
// ios/Flutter/Secrets.xcconfig) and reach the native map through the build.
void main() {
  test('Android reads the Maps key from local.properties into the manifest', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('rootProject.file("local.properties")'));
    expect(gradle, contains('getProperty("MAPS_API_KEY")'));
    expect(gradle, contains('manifestPlaceholders["mapsApiKey"]'));

    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      contains(
        '<meta-data\n'
        '            android:name="com.google.android.geo.API_KEY"\n'
        r'            android:value="${mapsApiKey}" />',
      ),
    );
    expect(File('android/.gitignore').readAsStringSync(), contains('/local.properties'));
  });

  test('iOS reads the Maps key from an ignored Secrets.xcconfig', () {
    for (final config in ['Debug', 'Release']) {
      expect(
        File('ios/Flutter/$config.xcconfig').readAsStringSync(),
        contains('#include? "Secrets.xcconfig"'),
        reason: config,
      );
    }
    expect(
      File('ios/.gitignore').readAsStringSync(),
      contains('Flutter/Secrets.xcconfig'),
    );
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains('<key>GMSApiKey</key>\n\t<string>\$(MAPS_API_KEY)</string>'),
    );

    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(appDelegate, contains('import GoogleMaps'));
    expect(appDelegate, contains('forInfoDictionaryKey: "GMSApiKey"'));
    expect(appDelegate, contains('GMSServices.provideAPIKey(mapsApiKey)'));
  });

  test('iOS targets 15.0, which Google Maps SDK 9 needs', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final targets = RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
    ).allMatches(project).map((match) => match.group(1)).toSet();
    expect(targets, {'15.0'});
  });

  // Firebase's google-services.json carries its own key by design: it ships
  // inside every Firebase app. Any other key in the repo is a leak.
  test('no Google API key is committed outside google-services.json', () {
    final tracked = Process.runSync('git', ['ls-files', '-z', '.']);
    expect(tracked.exitCode, 0);
    final offenders = <String>[];
    for (final path in (tracked.stdout as String).split('\x00')) {
      if (path.isEmpty || path.endsWith('google-services.json')) {
        continue;
      }
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() > 2 * 1024 * 1024) {
        continue;
      }
      final String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException {
        continue; // Binary file.
      }
      // Google API keys start with "AIza" and are 39 characters long.
      if (RegExp(r'AIza[0-9A-Za-z_\-]{35}').hasMatch(text)) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty);
  });
}
