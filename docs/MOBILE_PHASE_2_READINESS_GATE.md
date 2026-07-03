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

## M1BH Phone/PIN Auth Contract Readiness

The finalized CC4A-AUTH-FIX backend contract confirms that Ghana pilot mobile login remains phone number plus PIN, not email/password.

Documented login request payload:

```json
{
  "phone": "+233551234567",
  "pin": "1234"
}
```

Validation expected by the backend:

- Phone uses `+233` followed by 9 digits.
- PIN is a string of exactly 4 numeric digits.

The login success response includes `access`, `refresh`, `account_type`, and `account`. The mobile auth foundation must parse `account_type` and validate it against the expected app context.

Expected app contexts:

- Passenger App expects `passenger`.
- Driver App expects `driver`.
- Passenger and Driver app contexts must reject `staff`.
- Unknown or missing `account_type` must fail safely.

## Passenger Offline Queue Decision

Passenger ride requests must not be silently queued offline.

If the Passenger App has no network during ride request submission, it must show a clear error and retry action.

The Passenger App must not add `asm_offline_queue` support for booking submission unless the PM explicitly approves a future change.

The Driver App keeps offline queue support because driver operational events may occur during active service and must sync when connectivity returns.

## Future MTN MoMo Login Phone Prefill Note

After successful phone/PIN login, the authenticated profile phone number may be used to pre-populate the MTN MoMo payment phone field during the future ride payment flow.

This must be included in the future M2A/payment-flow brief.

The passenger should be able to edit the payment phone number if the payer uses a different mobile money number, unless backend/payment policy later says otherwise.

No payment UI is built by M1BH.
