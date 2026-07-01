# CC4A/CC4B Disabled Mobile Integration Map

Task M1AZ maps the future Control Center mobile integration dependencies without
starting M2A or adding live API behavior.

This is a guardrail task only.

## Dependency Map

| Dependency | Purpose | Status |
| --- | --- | --- |
| CC4A — Mobile auth API | Future controlled mobile authentication dependency | disabled / pending Control Center handoff |
| CC4B — Ride request API | Future Passenger ride request dependency | disabled / pending Control Center handoff |

## Mobile Guardrail State

The mobile repository records these dependencies in `asm_app_config` as disabled
future capabilities:

```text
mobileAuthApiEnabled = false
rideRequestApiEnabled = false
CC4A Mobile auth API pending
CC4B Ride request API pending
```

No endpoint URLs, tokens, secrets, base URLs, API clients, live login, ride
request submission, or UI wiring are added by this task.

## M2A Remains Blocked

M2A must remain blocked until both dependencies are accepted:

```text
CC4A Mobile auth API is complete, tested, documented, accepted, and handed over.
CC4B Ride request API is complete, tested, documented, accepted, and handed over.
```

The Mobile PM must receive written confirmation from the Control Center PM
before M2A starts.

## Forbidden Until Handoff

Until CC4A and CC4B are accepted and handed over, developers must not add:

- live authentication
- token writing
- backend/API calls
- endpoint URLs
- booking submission
- ride request submission
- request_reference persistence
- payment
- wallet
- GPS
- maps
- WebSocket
- dispatch
- driver assignment
- trip status
- notifications
- offline queue UI
- Passenger App to Driver App communication

## Scope Confirmation

This map is documentation and disabled app configuration only. It does not
change Passenger App source, Driver App source, backend/Django files, native
Android/iOS files, pubspec files, runtime behavior, or live integrations.
