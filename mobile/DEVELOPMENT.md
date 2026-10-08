# Mobile Development Environment

This document records the standard operational conventions for Mobile development and physical iOS QA.

## Terminal target labels

Every terminal instruction must be clearly labeled:

- `LOCAL MAC`
- `PRODUCTION SERVER`

Always verify the target before running a command.

## 1. Physical iOS debug launch

Installed Flutter debug builds on physical iOS devices may not remain normally launchable from the iOS Home screen.

For authorized physical QA, launch the app through Flutter tooling rather than relying on a Home-screen launch.

The currently grounded physical QA device identifier is:

```text
00008101-001A6C800150001E
```

This is the currently grounded QA device identifier only. It is not a universal identifier for future devices; re-ground the device identifier when the QA device changes.

## 2. API base URL

Production-connected Mobile QA must explicitly use:

```text
--dart-define="ASM_API_BASE_URL=https://control.alanteh.io"
```

Use another environment only when it is specifically authorized.

Omitting this configuration has previously produced:

```text
Connection is not configured yet.
```

Do not assume the production API base URL is embedded in the app.

## 3. Xcode / Flutter project hygiene

Flutter and Xcode tooling can automatically modify:

```text
ios/Runner.xcodeproj/project.pbxproj
```

and related Xcode metadata during build, launch, or compatibility upgrades.

Before any Git operation:

1. Inspect the worktree.
2. Review Xcode metadata changes.
3. Exclude unrelated generated or compatibility changes from the task unless they are explicitly authorized.

Never include unrelated Xcode changes in a task commit.

## 4. `devicectl` diagnostic noise

`CoreDeviceError Code=1002` must never, by itself, be classified as a QA failure.

Determine PASS or FAIL from the actual requested install, query, or uninstall outcome. Scary-looking diagnostic noise does not override a decisive successful operation result such as a successful app install, uninstall, or installed-app query.

## 5. Standard physical-iOS QA command pattern

These examples use the currently grounded physical QA device identifier above.

### LOCAL MAC — Passenger

```bash
cd mobile/apps/passenger_app && \
flutter run \
  -d 00008101-001A6C800150001E \
  --debug \
  --dart-define="ASM_API_BASE_URL=https://control.alanteh.io"
```

### LOCAL MAC — Driver

```bash
cd mobile/apps/driver_app && \
flutter run \
  -d 00008101-001A6C800150001E \
  --debug \
  --dart-define="ASM_API_BASE_URL=https://control.alanteh.io"
```

Keep the relevant `flutter run` session attached during authorized physical QA unless the QA procedure explicitly directs otherwise.

## 6. Android release signing

Release builds of both apps are signed with each app's own release key,
never the debug key: the Google Maps API keys are restricted to the
release certificate's SHA-1. A release build fails with "No release
signing configured" until a signing file exists.

Gradle reads the first of these that exists (never commit either):

1. `apps/<app>/android/key.properties` (git-ignored), or
2. `~/.config/alanteh/signing/passenger.properties` /
   `~/.config/alanteh/signing/driver.properties` — outside every checkout,
   so all worktrees on the Mac share them.

Each file holds:

```text
storeFile=/Users/<you>/.config/alanteh/keystores/alanteh-passenger-release.jks
storePassword=<password>
keyAlias=passenger-release
keyPassword=<password>
```

The keystores live in `~/.config/alanteh/keystores/` (mode 700), outside
every repository. Back each keystore and its password up somewhere safe:
losing them means a new key, a new SHA-1 and new Maps key restrictions.

Check what a build is signed with:

```bash
cd apps/passenger_app/android && ./gradlew signingReport
```

A release-signed build cannot be installed over a debug-signed one on a
device: uninstall the old app first (this signs the passenger out).

## 7. Google Maps keys (passenger app)

The passenger map is a Google map (`packages/asm_maps`). Each platform
has its own key, restricted to the app; neither is ever committed. Without
a key the app builds and runs, but the map stays blank.

- **Android:** add to the git-ignored
  `apps/passenger_app/android/local.properties`:

  ```text
  MAPS_API_KEY=<Android Maps key>
  ```

  Restrict the key to Maps SDK for Android, package `io.alanteh.passenger`
  and the release SHA-1 from `./gradlew signingReport` (section 6). Debug
  builds need the debug SHA-1 added as well. `local.properties` belongs to
  one checkout, so each new worktree needs the line again.

- **iOS:** create the git-ignored
  `apps/passenger_app/ios/Flutter/Secrets.xcconfig`:

  ```text
  MAPS_API_KEY = <iOS Maps key>
  ```

  Restrict the key to Maps SDK for iOS and the app's bundle ID. The app
  needs iOS 15 or later (Google Maps SDK 9).

In widget tests the map is a stand-in (`package:asm_maps/testing.dart`),
installed for every test by `test/flutter_test_config.dart`.

Device checks from China need the phone's VPN on: Google Maps, Places and
OpenStreetMap are blocked there, while the ALANTEH backend is not.

## 8. Driver trip map

The driver trip map is a Google map too (`packages/asm_maps`), showing only
real data: the pickup pin, the destination pin once the driver has
accepted, and the driver's own position ("you" dot). No route, distance or
time is drawn; Navigate hands off to the Google Maps app.

Keys work as in section 7, for the driver app:
`apps/driver_app/android/local.properties` (`MAPS_API_KEY=...`, restricted
to Maps SDK for Android, package `io.alanteh.driver` and its SHA-1s) and
`apps/driver_app/ios/Flutter/Secrets.xcconfig`. The driver app also needs
iOS 15 or later. Debug test builds need the API base URL from section 2;
without it the app opens on "Invalid argument (baseUrl)".

The camera follows `asmCameraFit` (`packages/asm_maps`): the leg's pin is
always in view; a driver more than 50 km from it is left out of the frame
(Google cannot zoom out far enough to show both and would sit over the
middle of them); within 150 m the map shows the pin close up.

Device check status (Android, 8 Oct 2026, commit 1513218, debug build
SHA-256 475a45e3):

- Verified: the pickup pin shows close up on first open; Navigate opens
  the Google Maps app with directions to the pickup; the camera holds on
  the pickup while there is no location fix.
- **Not verified on a device:** the camera after a real location fix far
  from the pickup (it should stay close up on the pin, not move to the
  sea), and the "you" dot after that fix. The test phone had no location
  fix that day. Re-check both at the next booking-based phone test, after
  confirming the phone has a fix (blue dot in Google Maps) before booking.
