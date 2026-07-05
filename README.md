# Africa Solar Mobility Mobile Platform

Task M1A establishes one Flutter repository with separate Passenger and Driver
applications for the controlled Ghana pilot.

## Applications

- `mobile/apps/passenger_app`: local Passenger shell
- `mobile/apps/driver_app`: local Driver shell

Both applications are independent deployable products. Their current screens
are local placeholders only and do not connect to live services.

## Integration Boundary

The existing Django Command Center remains the future backend foundation and is
outside this repository. No Django source, API integration, authentication,
booking, dispatch, maps, GPS, payments, wallets, earnings, or notifications are
implemented in M1A.

Future shared Dart packages may live under `mobile/packages` for design tokens,
API contracts, validation, localization, secure storage, and common domain
types. Empty packages are intentionally not created in this task.

## Local Verification

Run formatting from the repository root:

```bash
dart format --output=none --set-exit-if-changed mobile/apps
```

Run analysis, tests, and builds from each application directory:

```bash
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

Android is the primary pilot platform. iOS is supported from the same Flutter
codebase when a suitable macOS and Xcode environment is available.

## Shared API Client Foundation

Task M1AR adds `mobile/packages/asm_api_client` as a shared HTTP foundation for
future Django Control Center communication. The package is a foundation layer
only: it does not submit bookings, perform login, store tokens, open WebSockets,
read GPS, process payments, or connect Passenger App directly to Driver App.

The client accepts a configurable base URL. A safe compile-time default is
available for local development and tests only:

```bash
--dart-define=ASM_API_BASE_URL=https://your-control-center-domain.com
```

Production apps must provide the correct Django Control Center API base URL at
build or runtime configuration time. No production secrets, API keys, access
tokens, refresh tokens, or credentials are committed in this repository.

Authentication storage is implemented in the later `asm_auth` foundation package.
The API client remains storage-agnostic through the `TokenProvider` interface:
when a token is available, the client sends `Authorization: Bearer <token>`;
when no token is available, requests are sent without an Authorization header.

## Shared Authentication Foundation

Task M1AS adds `mobile/packages/asm_auth` as a shared authentication foundation
for future controlled Passenger and Driver login work.

The package adds secure token storage foundation using `flutter_secure_storage`
and defines mock-tested authentication service behavior for login, refresh,
logout, and current session checks. It depends on the local `asm_api_client`
package so future endpoint calls can be routed through the shared API client.

This is mock-tested infrastructure only. No live Control Center or Django
authentication endpoint is connected yet. No production credentials, API keys,
access tokens, refresh tokens, PINs, or secrets are committed in this repository.

No public registration, signup, booking submission, dispatch logic, ride request
creation, GPS, maps, geocoding, WebSocket tracking, payment, Mobile Money,
wallet, earnings, push notifications, passenger contact, driver contact,
persistent trip state, backend/Django code, or direct Passenger App to Driver
App communication is added in M1AS.

## Shared Ride Domain Fare, Payment, and Rating Vocabulary

Task M1AT expands `mobile/packages/asm_ride_domain` with shared domain
vocabulary for future fare display, payment status, payment method, service
context backend-code mapping, and trip rating draft data.

This package remains domain only. It adds no live payment behavior, no live
booking behavior, no API calls, no payment provider integration, and no app-owned
fare, payment, rating, trip-state, wallet, earnings, or operational-history
truth. The future Django Control Center backend remains the source of truth for
fares, payments, ratings, bookings, trip states, and operational records.

## Shared Offline Queue Foundation

Task M1AU adds `mobile/packages/asm_offline_queue` as a shared local event queue
foundation for future Driver App offline trip-event handling.

The package is local queue infrastructure only. It defines queued event data,
local retry state, FIFO queue handling, and a sync-client abstraction that is
mock-tested with fake clients only. It adds no live Django sync, no real backend
API calls, no trip status update submission, no Driver App live trip behavior,
and no Driver App UI badge yet.

Task M1AV extends the same package with a local queue status summary, a pending
badge count helper for future UI work, a connectivity abstraction, and
fake/mock connectivity tests. Connectivity is checked only through local test
fakes in this task. There is no `connectivity_plus` wrapper, no background
service, no timer, no automatic background sync, no live Django sync, no real
backend API call, no Driver App UI badge yet, and no trip status submission.

The Driver App depends on the package so future controlled tasks can use it, but
this task does not connect it to any Driver UI flow. The future Django Control
Center backend remains the source of truth for trip state, dispatch, payment,
wallet, earnings, fare, and operational history.


## Passenger and Driver Login Screen Shells

Task M1AW adds controlled Passenger App and Driver App login screen shells for
local demo use only.

The screens collect phone number and PIN values for UI validation only. They do
not connect to a live Django auth endpoint, do not call a real backend API, do
not write tokens from app UI, and do not create real sessions.

No public registration, signup, OTP, account creation, password reset, booking
submission, ride request API integration, driver assignment, dispatch logic,
trip status update, payment, Mobile Money, wallet, earnings, fare calculation,
GPS, Google Maps, geocoding, WebSocket, offline queue UI badge, notifications,
passenger contact, driver contact, persistent trip state, backend/Django code,
native Android/iOS source change, or direct Passenger App to Driver App
communication is added in M1AW.

Existing local demo flows remain available after the user continues through the
local demo login shell.

## Login Shell Local Demo Entry Polishing

Task M1AX keeps the Passenger App and Driver App login shells as mock local demo
UI only while polishing the local demo entry behavior.

The real app entry points still show the login shells first. The Continue local
demo action validates the local phone number and PIN fields and then opens the
existing demo app screens only. The Clear form action clears the phone value, PIN
value, and any visible validation messages.

No live authentication, token writing, backend/API calls, registration, signup,
OTP, password reset, package change, pubspec change, native Android/iOS source
change, backend/Django work, booking, dispatch, trip status, maps, GPS,
WebSocket, payment, wallet, earnings, notifications, offline queue UI, real
session persistence, or Passenger App to Driver App communication is added in
M1AX.

## Mobile Phase 2 Readiness Gate

Task M1AY adds the documentation-only Phase 2 readiness gate at
`docs/MOBILE_PHASE_2_READINESS_GATE.md`.

Phase 2 live mobile work is blocked until CC4A and CC4B are accepted and handed
over by the Control Center PM.

## CC4A/CC4B Disabled Mobile Integration Map

Task M1AZ maps CC4A and CC4B as disabled future mobile dependencies only. The
map is documented in `docs/MOBILE_CC4A_CC4B_DISABLED_MAP.md` and represented in
`asm_app_config` with disabled guardrail constants.

CC4A Mobile auth API and CC4B Ride request API remain pending Control Center PM
handoff. M2A must not begin until both APIs are complete, tested, documented,
accepted, and handed over.

## Disabled API Client Guard For CC4A/CC4B

Task M1BA adds a disabled api client guard in `asm_api_client` for future CC4A
and CC4B mobile integration work.

CC4A and CC4B remain disabled. M2A remains blocked until Control Center PM
handoff. No live mobile API integration was added.

## Disabled Auth Guard For CC4A

Task M1BB added a disabled auth guard only.

CC4A Mobile auth remains disabled.

M2A remains blocked until Control Center PM handoff.

No live mobile authentication was added.

## Driver Dark Theme Token Consolidation

Task M1BC consolidated Driver dark login-shell colors into asm_design_system tokens only.

No runtime behavior changed.

No live API work was added.

## M1BE Future Passenger Payment Rule

When the Passenger App payment screen is eventually built, MTN MoMo must be pre-selected by default for Ghana Accra. Passengers should only need to change provider if they use Telecel Cash or AirtelTigo Money.

## M1BF Payment Domain Alignment

M1BF aligned mobile payment provider backend codes with the Control Center/Paystack provider-code direction:
MTN MoMo -> mtn
Telecel Cash -> vod
AirtelTigo Money -> atl

M1BF also aligned payment confirmed status to payment_confirmed and added partnerPaid -> partner_paid.
No payment screen or live payment integration was added.

## M1BG Mobile Visual QA Evidence Pack

M1BG added a visual QA evidence pack only.
No runtime behavior changed.
No app source files changed.
M2A remains blocked until CC4A and CC4B Control Center handoff.

## M1BH Phone/PIN Auth Readiness

M1BH confirmed mobile auth remains phone/PIN to match the finalized CC4A-AUTH-FIX backend contract.

The documented CC4A login request payload is:
phone + pin

Auth response handling now includes account_type parsing and expected app-context validation.

Passenger App expects passenger account context.
Driver App expects driver account context.

Passenger offline queue decision and future MTN MoMo login-phone prefill note were added to the Phase 2 readiness gate.

No email/password conversion, live API call, token writing from app UI, Django connection, or M2A behavior was added.

## M1BI Passenger Booking UX Simplification

M1BI simplified the Passenger booking UI before M2A.

Passenger-facing engineering labels were removed.

The service context dropdown was removed from Passenger UI.

The booking form now uses plain passenger language.

The confirm screen shows MTN MoMo as the default payment method display only.

No backend/API call, live booking submission, payment integration, maps, GPS, or new package was added.

Future pilot UX decision: pickup and destination may become predefined approved-location lists before live launch, because GPS/maps are not yet integrated and free text may increase dispatcher uncertainty.


## M1BJ — ALANTEH Brand Rename and Driver UX Cleanup

M1BJ applied the confirmed ALANTEH visible brand direction across the mobile apps.

Driver App UI labels were simplified for field use. Driver-facing engineering/demo markers were removed. Passenger visible brand wording was aligned where needed.

No backend/API call, live booking, live trip acceptance, payment integration, GPS/maps, WebSocket, new package, native change, or Django change was added.

### M1BK future Ghana service-area note

Future location task: the app should detect or receive the active Ghana city/service area dynamically, for example Accra, Kumasi, Tamale, Takoradi, Cape Coast, or another approved service city. This must be handled in a separate approved location/GPS/backend/service-area task.

M1BK does not add city auto-detection. M1BK does not add GPS, geolocation permissions, reverse geocoding, maps, backend lookup, or new packages.

### M2A Passenger ride request submission wiring

M2A wires the Passenger booking confirmation path to the accepted CC4B backend contract only: `POST /api/rides/request/` with the existing CC4A bearer-token direction and an `Idempotency-Key` header. The mobile request payload sends only `pickup_location`, `destination`, `passenger_count`, and optional `assistance_note`; it omits `service_context` and does not send payment, GPS, driver, status, or request_reference fields.

M2A does not add Driver dispatch, assignment, trip polling, payment processing, MTN MoMo API, Paystack, GPS, maps, geolocation, reverse geocoding, WebSocket, wallet, push notification, backend/Django, native, pubspec, new package, or Passenger offline queue behavior.

### M2B — Passenger Phone/PIN Login Token Wiring

M2B wires the Passenger App login screen to the accepted CC4A phone/PIN token contract. Passenger login uses `POST /api/auth/token/` with `phone` and `pin`, accepts only `account_type: passenger`, stores returned access/refresh tokens through the existing mobile auth token store, and lets M2A ride request submission use the stored Passenger access token. Ride request submission is blocked before POST when no Passenger access token exists, with the passenger-safe message `Please sign in to request a ride.`

M2B does not add Driver login integration, dispatch, trip polling, payment processing, GPS, maps, WebSocket, Passenger offline queue behavior, backend/Django files, native Android/iOS files, pubspec changes, or new packages.

### M2C — Driver Phone/PIN Login Token Wiring

M2C wires the Driver App login shell to the accepted CC4A phone/PIN auth contract. The Driver App uses `POST /api/auth/token/` through the shared auth service, sends only `phone` and `pin`, accepts only `account_type = driver`, stores returned access/refresh tokens through the existing auth token store, clears PIN entry, and keeps `Continue without signing in` as a separate local QA path. No backend, native, pubspec, dispatch, trip polling, GPS, maps, payment, WebSocket, wallet, or new package work is included.

### M2D — Authenticated Session Sign-Out and Token Clear

M2D adds visible Passenger and Driver sign-out actions using the existing auth token store. Sign out clears stored access and refresh tokens, returns the user to the relevant login screen, keeps Driver local shift state reset by remounting the Driver shell, and preserves `Continue without signing in` as a separate token-free local QA path. No backend logout endpoint, token refresh behavior, live session validation, native, pubspec, package, dispatch, GPS, maps, payment, WebSocket, wallet, or offline queue behavior change is included.

### M2E — Auth Session Restore and Expired Token Recovery

M2E restores Passenger and Driver sessions on app startup using the existing stored auth tokens. Passenger ride request submission now handles one 401 response by refreshing the access token through `POST /api/auth/token/refresh/`, storing the new access token, and retrying the same ride request once with the same `Idempotency-Key`. Missing or failed refresh clears stored tokens and returns the Passenger to the sign-in-required path. No backend logout, live session validation, native, pubspec, package dependency, dispatch, GPS, maps, payment, WebSocket, wallet, or offline queue behavior change is included.

### M2F — Mobile API Base URL Wiring and Live Smoke-Test Readiness

M2F wires Passenger and Driver live API calls to the Flutter dart-define value `ASM_API_BASE_URL`. No production backend URL, secrets, tokens, or credentials are hardcoded in source.

Passenger live QA example:

    cd mobile/apps/passenger_app
    flutter run -d "<simulator-id>" --dart-define=ASM_API_BASE_URL=https://your-control-center-domain.com

Driver live QA example:

    cd mobile/apps/driver_app
    flutter run -d "<simulator-id>" --dart-define=ASM_API_BASE_URL=https://your-control-center-domain.com

If the API base URL is missing or invalid during real sign-in or ride request submission, the apps show `Connection is not configured yet.` Continue without signing in remains local-only and does not require API configuration.

M2L gates the local QA entry behind `ASM_ENABLE_LOCAL_QA`. Live builds should omit it:

    flutter run --dart-define=ASM_API_BASE_URL=https://your-control-center-domain.com

Local QA may enable the local-only entry explicitly:

    flutter run \
      --dart-define=ASM_API_BASE_URL=https://example.test \
      --dart-define=ASM_ENABLE_LOCAL_QA=true

M2M keeps Passenger and Driver login on the accepted CC4A format: phone must be `+233` followed by 9 digits, and PIN must be exactly 4 numeric digits before the apps call the backend.

M2N keeps the Driver signed-in home safe for live QA. By default it shows `No trip assigned yet.` and `Stay ready for the Control Center.` while hiding the local trip preview and local accept action. The local trip preview remains available only when `ASM_ENABLE_LOCAL_QA=true`.

M2O aligns Passenger and Driver app colors with the ALANTEH logo color direction. The shared design system promotes `#2F5233` as `AsmColors.brandGreen` and `#000000` as `AsmColors.brandBlack`. The earlier visual logo reference pack was used only as color reference; no logo image assets, app icons, splash screens, native launcher files, pubspec changes, or new packages were added in M2O.

M2P improves the Passenger ride receipt by letting the passenger copy the real backend `request_reference` and by showing `Keep this reference. The Control Center can use it to follow up.` The app copies only the backend reference value and does not generate fake references or copy route, passenger, token, or backend URL data.

M2Q completed a Passenger and Driver live QA visual inspection after M2O ALANTEH color alignment and M2P receipt copy support. Visual proof was captured separately outside the source tree. No app screenshots, logo assets, app icons, splash screens, native files, pubspec files, backend files, or new packages are added.

M2R integrates the accepted ALANTEH final app icon and logo assets into the Passenger and Driver apps. The app brand green is updated to `#275C2E`, in-app header logo assets are declared per app, native launcher and splash assets are updated directly, and the source logo ZIP remains outside the repository and candidate package.
