# Ghana Network Resilience — Passenger

## Exact Ghana connectivity baseline

- `connectivity_plus` 7.3.0 is installed and used for network-interface state.
- The app distinguishes no interface, cellular, Wi-Fi, ethernet, VPN,
  satellite, Bluetooth, other, and mixed interface states.
- Connectivity type is not treated as proof of Internet access. The interface
  signal is combined with the configured ALANTEH API-host reachability probe,
  request timeouts, latency, and actual request outcomes.
- The connectivity stream is checked again when the app resumes, because
  Android does not deliver background connectivity changes reliably.
- A clear offline banner appears without deleting the current screen or booking
  details.

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
   path

Safe work means:

- `GET`
- `HEAD`
- a request carrying a non-empty `Idempotency-Key`

Unsafe non-idempotent POST work is never retried automatically. JSON API
requests continue to negotiate `Accept-Encoding: gzip`.

## Passenger booking behavior

- The accepted `Sending request...` state is preserved.
- Entered booking details remain available after offline or timeout failure.
- The same idempotency key is reused for the existing manual retry path.
- Passenger booking is not stored in an offline submission queue. A ride
  request has server-side dispatch consequences, and silently submitting it
  later without an accepted backend queue contract or fresh passenger intent
  could create an unwanted ride. The UI therefore keeps details and presents a
  clear manual retry path instead.

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

FMTC is therefore not added to the production apps in this correction. Forcing
a cached plugin patch or downgrading the accepted Android toolchain is outside
this task and would create an unsupported dependency fork.

Greater Accra prefetch at zoom levels 12–16 is also not performed against the
current public `tile.openstreetmap.org` source. The OpenStreetMap tile policy
prohibits pre-seeding regions, multiple zoom stacks, and offline bulk download.
A future cache task requires all of the following:

1. an approved tile provider or self-hosted source that explicitly permits
   offline/prefetch use;
2. a build-compatible caching backend;
3. PM/legal approval for FMTC's GPL-3.0 terms or an approved alternative
   license;
4. a separately approved Greater Accra operating-zone boundary and storage
   budget.

Normal interactive map viewing and standards-compliant repeat-view caching
remain available. No offline navigation or Greater Accra prefetch claim is
made.

## Build-size evidence

Step 5J-C verification records Android debug APK size and split release APK
sizes. Generated APKs are proof outputs only and are not added to Git.

## Boundaries

No backend, Control Center, public website, or shared package is changed.
