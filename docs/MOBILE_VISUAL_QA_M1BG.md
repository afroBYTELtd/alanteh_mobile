# M1BG Mobile Visual QA Evidence Pack

Task: M1BG — Mobile Visual QA Evidence Pack — Current Local Demo Apps

Baseline:
- Africa-Solar-Mobility-Mobile-M1BF-candidate.zip
- SHA-256: dd1793fb5ce5246d0b712de3c19e08393ad47b12d86fb5cc9da8c87ec026568e
- GitHub main/tag commit: 67522e1eeb5b35027fab7e738920038bcde6cdd9
- Accepted tag: m1bf-accepted

## QA environment

Date of QA run:
- Fri Jul 3, 2026

Device/simulator used:
- iPhone 17 simulator
- iOS 26.4 simulator runtime
- Device id: 57786036-5231-4F3E-BDFD-122DDD6AF7C3

Flutter version:
- Flutter 3.44.2 stable
- Dart 3.12.2

Screenshot folder:
- ~/Workspace/ASM-Mobile-M1BG-Screenshots

Screenshots are not included in the candidate ZIP.

## Passenger App run result

Passenger App command checks:
- flutter clean: PASS
- flutter pub get: PASS
- flutter analyze: PASS
- flutter test: PASS, 29 tests
- flutter run on iPhone 17 simulator: PASS

Passenger App visual run result:
- Passenger login shell appears first: PASS
- Continue local demo works: PASS
- Passenger local demo home is reachable: PASS
- Passenger location search screen is reachable: PASS
- Passenger booking form is reachable: PASS
- Passenger booking review screen is reachable: PASS
- No screen suggests live authentication is active: PASS
- No screen suggests real booking submission is active: PASS
- No screen suggests payment is live: PASS
- No Paystack or direct mobile money payment UI appears: PASS
- No GPS, maps, or WebSocket live tracking UI appears: PASS
- No Passenger-to-Driver direct communication appears: PASS

Passenger Clear form / draft observation:
- Passenger login shell includes a Clear form action.
- Passenger booking review screen does not show an action labeled Clear form.
- The visible booking review exit action is Close draft.
- Close draft returns the user to Passenger home and does not crash.
- This is documented as a visual QA wording and flow observation only. No fix was applied in M1BG.

## Driver App run result

Driver App command checks:
- flutter clean: PASS
- flutter pub get: PASS
- flutter analyze: PASS
- flutter test: PASS, 27 tests
- flutter run on iPhone 17 simulator: PASS

Driver App visual run result:
- Driver login shell appears first: PASS
- Continue local demo works: PASS
- Driver local demo home is reachable: PASS
- Driver pre-shift readiness checklist is reachable: PASS
- Driver vehicle concern form is reachable: PASS
- Driver ride offer preview is reachable: PASS
- No screen suggests live authentication is active: PASS
- No screen suggests real dispatch is active: PASS
- No screen suggests real booking submission is active: PASS
- No screen suggests payment is live: PASS
- No Paystack or direct mobile money payment UI appears: PASS
- No GPS, maps, or WebSocket live tracking UI appears: PASS
- No Passenger-to-Driver direct communication appears: PASS

Driver Clear form / local demo observation:
- Driver login shell includes a Clear form action.
- Driver workflow screens use context-specific local demo actions, including Reset checklist, Close draft, and Close preview.
- These actions were observed as local demo actions only and did not show live backend behavior.
- This is documented as a visual QA observation only. No fix was applied in M1BG.

## Screenshot evidence list

Passenger screenshots saved locally:
1. passenger_01_login_shell.png — Passenger login shell.
2. passenger_02_local_demo_home.png — Passenger local demo home after Continue local demo.
3. passenger_03_location_search.png — Passenger location search screen.
4. passenger_04_booking_form.png — Passenger booking form.
5. passenger_05_booking_review.png — Passenger booking review screen.

Driver screenshots:
1. driver_01_login_shell.png — Driver login shell, saved locally.
2. driver_02_local_demo_home.png — Driver local demo home after Continue local demo, provided in chat as visual QA evidence.
3. driver_03_pre_shift_readiness.png — Driver pre-shift readiness checklist, provided in chat as visual QA evidence.
4. driver_04_vehicle_concern_form.png — Driver vehicle concern form, provided in chat as visual QA evidence.
5. driver_05_ride_offer_preview.png — Driver ride offer preview, provided in chat as visual QA evidence.

Supplementary Driver visual evidence provided in chat:
- Driver vehicle concern review / draft screen.
- Driver ride offer accepted preview state.
- Driver ride offer declined preview state.

## Shared package checks

- asm_api_client analyze: PASS
- asm_api_client test: PASS, 17 tests
- asm_auth analyze: PASS
- asm_auth test: PASS, 15 tests
- asm_app_config analyze: PASS
- asm_app_config test: PASS, 15 tests
- asm_design_system analyze: PASS
- asm_design_system test: PASS, 60 tests
- asm_ride_domain analyze: PASS
- asm_ride_domain test: PASS, 40 tests
- asm_offline_queue analyze: PASS
- asm_offline_queue test: PASS, 21 tests

## Visual findings

- Passenger and Driver apps launch to their login shells first.
- Continue local demo works in both apps.
- Passenger demo navigation reaches home, location search, booking form, and booking review screens.
- Driver demo navigation reaches home, readiness checklist, vehicle concern flow, and ride offer preview screens.
- Demo wording remains local-demo oriented.
- No screen indicates live authentication, live booking submission, payment, Paystack integration, GPS or maps live tracking, WebSocket activity, wallet activity, notification activity, or direct Passenger-to-Driver communication.

## Visual issues or observations

Observation 1:
- Passenger booking review uses Close draft instead of a button labeled Clear form.
- Close draft returns to Passenger home and does not submit a ride request.
- No code change was made.

Observation 2:
- Driver workflow screens use context-specific actions such as Reset checklist, Close draft, and Close preview rather than a universal Clear form action on every workflow screen.
- No code change was made.

## PM recommendation

Accept M1BG as a documentation and evidence-only task if:
- README.md and docs/MOBILE_VISUAL_QA_M1BG.md are the only changed files.
- Packaging has zero forbidden artifacts.
- The final ZIP excludes generated verification artifacts and screenshots.
- The visual observations above are treated as future UX review notes, not as M1BG blockers.

M2A remains blocked until CC4A and CC4B Control Center handoff.
