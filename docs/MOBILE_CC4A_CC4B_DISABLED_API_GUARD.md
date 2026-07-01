# CC4A/CC4B Disabled API Guard

Task M1BA adds a local package guard inside `asm_api_client` for the future
CC4A Mobile auth API and CC4B Ride request API.

This is a disabled guardrail only. It does not start M2A.

## Disabled Dependencies

```text
CC4A Mobile auth API is disabled pending Control Center handoff.
CC4B Ride request API is disabled pending Control Center handoff.
```

M2A remains blocked until both APIs are complete, tested, documented, accepted,
and handed over by the Control Center PM.

## Guard Behavior

The `asm_api_client` package can represent these future mobile API dependencies
as unavailable:

```text
mobileAuthApiAvailable = false
rideRequestApiAvailable = false
```

When future work tries to require CC4A or CC4B before handoff, the guard returns
or throws the disabled handoff message instead of allowing the feature to be
treated as ready.

## No Live API Surface

This task defines no endpoint path, base URL, token, request_reference, payload
schema, Passenger App integration, Driver App integration, backend call, or
request submission behavior.

The guard is local/package-only and exists to stop accidental early use of CC4A
or CC4B before Control Center PM handoff.
