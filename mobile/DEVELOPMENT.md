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
