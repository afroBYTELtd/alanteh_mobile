# Mobile Phase 2 Readiness Gate

Task M1AY is a documentation and guardrail checkpoint only. It records the
current accepted mobile baseline and blocks Phase 2 live mobile work until the
required Control Center APIs are complete, tested, documented, and handed over.

No runtime behavior is changed by this readiness gate.

## Current Accepted Baseline

```text
Africa-Solar-Mobility-Mobile-M1AX-candidate-final.zip
SHA-256:
af0d2baaf3632176f6775b9f48e75c128a45db57a36c2164b421e60771d243bc
```

## Completed Mobile Foundation Status

The following mobile foundation items are complete as local/demo or foundation
work only:

- `asm_api_client` HTTP foundation
- `asm_auth` authentication foundation
- `asm_ride_domain` fare/payment/rating vocabulary
- `asm_offline_queue` local queue foundation
- Passenger login shell local demo UI
- Driver login shell local demo UI

These foundations do not start live Passenger ride request submission and do not
connect the mobile apps to live Control Center workflows.

## Current Blocked Task

The next official live task is:

```text
M2A — Passenger ride request submission
```

M2A must not begin until:

```text
CC4A Mobile auth API is complete and tested
CC4B Ride request API is complete and tested
```

## Required Confirmation Before M2A

Before M2A starts, the Mobile PM must receive written confirmation from the
Control Center PM that CC4A and CC4B are complete, tested, documented, and ready
for mobile integration.

## Forbidden Work Before CC4A and CC4B

Until CC4A and CC4B are accepted and handed over, the developer must not add:

- live ride request submission
- live login/auth connection
- real token writing from UI
- real backend/API calls from Passenger booking
- status polling
- request_reference persistence
- payment screen
- Mobile Money
- driver assignment
- dispatch
- trip status updates
- maps
- GPS
- WebSocket
- wallet
- earnings
- notifications
- passenger contact
- driver contact
- backend/Django changes
- native Android/iOS changes
- direct Passenger App to Driver App communication

## Future M2A Preparation Checklist

When CC4A and CC4B are ready, the PM must confirm:

- [ ] Confirm CC4A auth endpoint path
- [ ] Confirm CC4A request/response schema
- [ ] Confirm CC4A token refresh behavior
- [ ] Confirm CC4B ride request endpoint path
- [ ] Confirm CC4B request payload schema
- [ ] Confirm CC4B response schema including request_reference and status
- [ ] Confirm idempotency-key header or field requirement
- [ ] Confirm validation error format
- [ ] Confirm auth scoping rules
- [ ] Confirm test user credentials for sandbox
- [ ] Confirm base URL and environment configuration method
- [ ] Confirm no production secrets are committed

## Verification Commands For Next Handoff

Run formatting from the repository root:

```bash
dart format --set-exit-if-changed mobile/apps/passenger_app mobile/apps/driver_app mobile/packages
```

Run app checks:

```bash
cd mobile/apps/passenger_app
flutter analyze
flutter test

cd mobile/apps/driver_app
flutter analyze
flutter test
```

Run shared package checks:

```bash
cd mobile/packages/asm_api_client
flutter analyze
flutter test

cd mobile/packages/asm_auth
flutter analyze
flutter test

cd mobile/packages/asm_app_config
flutter analyze
flutter test

cd mobile/packages/asm_design_system
flutter analyze
flutter test

cd mobile/packages/asm_ride_domain
flutter analyze
flutter test

cd mobile/packages/asm_offline_queue
flutter analyze
flutter test
```

## Guardrail Summary

Phase 2 live mobile work remains blocked until CC4A and CC4B are accepted and
handed over by the Control Center PM. This checkpoint adds documentation only
and does not change Passenger App source, Driver App source, tests, pubspec
files, `pubspec.lock` files, shared package source, native Android/iOS files, or
backend/Django files.
