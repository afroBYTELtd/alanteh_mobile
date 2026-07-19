# Ghana Network Resilience — Driver

## Exact Ghana connectivity baseline

- `connectivity_plus` 7.3.0 is installed and used for network-interface state.
- The app distinguishes no interface, cellular, Wi-Fi, ethernet, VPN,
  satellite, Bluetooth, other, and mixed interface states.
- Connectivity type is not treated as proof of Internet access. The interface
  signal is combined with the configured ALANTEH API-host reachability probe,
  request timeouts, latency, and actual request outcomes.
- The connectivity stream is checked again when the app resumes.
- A clear offline banner appears without deleting Driver duty or trip data.

## Exact timeout and retry policy

Every resilient app-local API request uses a 15-second timeout profile:

- connect: 15 seconds
- send: 15 seconds
- receive: 15 seconds
- wall-clock request: 15 seconds

Automatic retry is limited to safe work only:

1. first attempt
2. wait 2 seconds, then retry
3. wait 4 seconds, then retry
4. wait 8 seconds, then make the final automatic attempt
5. if it still fails, return the failure to the existing friendly manual retry
   or refresh path

Safe work means `GET`, `HEAD`, or a request carrying a non-empty
`Idempotency-Key`. Unsafe non-idempotent POST work is never retried
automatically. JSON API requests continue to negotiate
`Accept-Encoding: gzip`.

## Offline Driver trip-action boundary

The accepted visual trip sequence retains its injectable local action recorder.
When that recorder reports the API host is unreachable, the visual action is
stored through the existing `asm_offline_queue` package and the Driver receives
an honest `Saved on this device` notice.

This queue remains local-only in Step 5J-C. It is not automatically submitted
when connectivity returns because no accepted live Driver trip-action endpoint,
payload contract, authenticated identity handoff, conflict policy, or server
idempotency contract was authorized for this mobile task. Pretending to sync
would risk changing real trip state incorrectly.

The queue-to-server worker must be implemented only in the separately assigned
Driver live trip-action synchronization task after the Mobile PM supplies the
accepted paths, events, schema, and authentication rules.

## Greater Accra map-cache compatibility decision

`flutter_map_tile_caching` 10.1.1 was tested independently in temporary copies
of both apps on the accepted mobile toolchain:

- Flutter 3.44.2
- Dart 3.12.2
- Android Gradle Plugin 9.0.1
- Kotlin 2.3.20
- Gradle 9.1.0
- Java 17

Dependency resolution succeeds, but Android debug builds fail through
`objectbox_flutter_libs` 4.3.1. That plugin declares
`compileSdkVersion 31`, while its resolved AndroidX dependencies require API
33 or 34. The failing task is
`:objectbox_flutter_libs:checkDebugAarMetadata`.

FMTC is therefore not added. Forcing a plugin patch, dependency override, or
Android toolchain downgrade is outside this correction and would create an
unsupported production dependency.

Greater Accra prefetch at zoom levels 12–16 is not performed against public
`tile.openstreetmap.org`, whose policy prohibits pre-seeding and offline bulk
download. A future cache task requires an approved provider or self-hosted tile
source, compatible storage, PM/legal licensing approval, an operating-zone
boundary, and a storage budget.

Normal interactive viewing and standards-compliant repeat-view caching remain
available. No offline navigation or Greater Accra prefetch claim is made.

## Build-size evidence

Step 5J-C verification records Android debug APK size and split release APK
sizes. Generated APKs are proof outputs only and are not added to Git.

## Boundaries

No backend, Control Center, public website, or shared package is changed. No
live Driver WebSocket or trip-action synchronization is added.
