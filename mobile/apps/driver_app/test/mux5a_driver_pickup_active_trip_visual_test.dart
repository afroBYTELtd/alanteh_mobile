import 'dart:async';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_offline_queue/asm_offline_queue.dart';
import 'package:driver_app/ride_offer/driver_ride_offer_page.dart';
import 'package:driver_app/trip_progress/driver_trip_route.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/driver_trip_action_resilience.dart';
import 'package:driver_app/safety/driver_trip_safety.dart';
import 'package:driver_app/trip_progress/driver_trip_visual_sequence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

const _authoritativePickup = 'Accra Mall';
const _authoritativeDestination = 'Kotoka International Airport';
const _authoritativePassengerCount = 1;

void main() {
  testWidgets('pickup route renders map, static pin, and details sheet', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTripSequence(tester);

    expect(find.byKey(const Key('driver-navigate-to-pickup')), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.byKey(const Key('driver-static-position-pin')), findsOneWidget);
    expect(find.byKey(const Key('driver-pickup-position-pin')), findsOneWidget);
    expect(
      find.byKey(const Key('driver-destination-position-pin')),
      findsNothing,
    );
    expect(find.text('Heading to pickup'), findsOneWidget);
    expect(find.text('Accra Mall'), findsWidgets);
    expect(find.textContaining('1.2 km'), findsOneWidget);
    expect(find.textContaining('about 5 min'), findsOneWidget);
  });

  testWidgets('pickup arrival and passenger-onboard confirmation work', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTripSequence(tester);

    await _tapVisible(
      tester,
      find.byKey(const Key('driver-mark-arrived-pickup')),
    );

    expect(find.byKey(const Key('driver-arrived-at-pickup')), findsOneWidget);
    expect(find.text("You've arrived"), findsOneWidget);
    expect(find.text('Confirm passenger onboard'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const Key('driver-open-onboard-confirmation')),
    );

    expect(
      find.byKey(const Key('driver-confirm-passenger-onboard')),
      findsOneWidget,
    );
    expect(find.text('Confirm passenger onboard'), findsOneWidget);
    expect(find.text('Start trip'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const Key('driver-cancel-onboard-confirmation')),
    );

    expect(find.byKey(const Key('driver-arrived-at-pickup')), findsOneWidget);
  });

  testWidgets('confirmed passenger opens active trip destination map', (
    tester,
  ) async {
    _useSurface(tester);

    await _openActiveTrip(tester);

    expect(find.byKey(const Key('driver-active-trip')), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('driver-static-position-pin')), findsOneWidget);
    expect(
      find.byKey(const Key('driver-destination-position-pin')),
      findsOneWidget,
    );
    expect(find.text('Trip in progress'), findsOneWidget);
    expect(
      find.text('Heading to Kotoka International Airport'),
      findsOneWidget,
    );
    expect(find.textContaining('9.5 km'), findsOneWidget);
    expect(find.textContaining('about 23 min'), findsOneWidget);
    expect(find.text('Arrived at destination'), findsOneWidget);
  });

  testWidgets('test_driver_accepted_note_card_visible', (tester) async {
    _useSurface(tester);

    await _pumpTripSequence(
      tester,
      initialStatus: 'driver_accepted',
      passengerNote: 'I am at the side entrance, blue jacket',
    );

    expect(
      find.byKey(const Key('driver-navigate-to-pickup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('driver-passenger-note-card')),
      findsOneWidget,
    );
    expect(find.text('Note from passenger'), findsOneWidget);
  });

  testWidgets('test_driver_accepted_exact_note_text', (tester) async {
    _useSurface(tester);

    await _pumpTripSequence(
      tester,
      initialStatus: 'driver_accepted',
      passengerNote: 'I am at the side entrance, blue jacket',
    );

    expect(
      find.text('I am at the side entrance, blue jacket'),
      findsOneWidget,
    );
  });

  testWidgets('test_driver_accepted_empty_note_hidden', (tester) async {
    _useSurface(tester);

    for (final note in <String?>[null, '', '   ']) {
      await _pumpTripSequence(
        tester,
        initialStatus: 'driver_accepted',
        passengerNote: note,
      );

      expect(
        find.byKey(const Key('driver-navigate-to-pickup')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-passenger-note-card')),
        findsNothing,
      );
      expect(find.text('Note from passenger'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('test_driver_accepted_note_above_pickup_action', (tester) async {
    _useSurface(tester);

    await _pumpTripSequence(
      tester,
      initialStatus: 'driver_accepted',
      passengerNote: 'I am at the side entrance, blue jacket',
    );

    final noteCard = find.byKey(const Key('driver-passenger-note-card'));
    final pickupAction = find.byKey(
      const Key('driver-mark-arrived-pickup'),
    );

    await tester.ensureVisible(noteCard);
    await tester.pump();

    expect(noteCard, findsOneWidget);
    expect(pickupAction, findsOneWidget);
    expect(
      tester.getBottomLeft(noteCard).dy,
      lessThan(tester.getTopLeft(pickupAction).dy),
    );
  });

  testWidgets('test_driver_trip_screen_shows_note_when_present', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTripSequence(
      tester,
      initialStatus: 'in_progress',
      passengerNote: 'I am at the side entrance, blue jacket',
    );

    expect(find.byKey(const Key('driver-active-trip')), findsOneWidget);
    expect(find.byKey(const Key('driver-passenger-note-card')), findsOneWidget);
    expect(find.text('Note from passenger'), findsOneWidget);
    expect(find.text('I am at the side entrance, blue jacket'), findsOneWidget);
  });

  testWidgets('test_driver_trip_screen_hides_note_when_absent', (tester) async {
    _useSurface(tester);

    for (final note in <String?>[null, '', '   ']) {
      await _pumpTripSequence(
        tester,
        initialStatus: 'in_progress',
        passengerNote: note,
      );

      expect(find.byKey(const Key('driver-active-trip')), findsOneWidget);
      expect(find.byKey(const Key('driver-passenger-note-card')), findsNothing);
      expect(find.text('Note from passenger'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('test_note_card_positioned_above_action_buttons', (tester) async {
    _useSurface(tester);

    await _pumpTripSequence(
      tester,
      initialStatus: 'in_progress',
      passengerNote: 'Meet me by the side entrance.',
    );

    final noteCard = find.byKey(const Key('driver-passenger-note-card'));
    final actionButton = find.byKey(
      const Key('driver-mark-arrived-destination'),
    );

    await tester.ensureVisible(noteCard);
    await tester.pump();

    expect(noteCard, findsOneWidget);
    expect(actionButton, findsOneWidget);
    expect(
      tester.getBottomLeft(noteCard).dy,
      lessThan(tester.getTopLeft(actionButton).dy),
    );
  });

  testWidgets('destination arrival completes the local visual sequence', (
    tester,
  ) async {
    _useSurface(tester);

    await _openActiveTrip(tester);

    await _tapVisible(
      tester,
      find.byKey(const Key('driver-mark-arrived-destination')),
    );

    expect(
      find.byKey(const Key('driver-arrived-at-destination')),
      findsOneWidget,
    );
    expect(find.text('Arrived at destination'), findsWidgets);
    expect(find.text('Complete trip'), findsOneWidget);

    await _tapVisible(tester, find.byKey(const Key('driver-complete-trip')));

    expect(find.byKey(const Key('driver-trip-completed')), findsOneWidget);
    expect(
      find.text('Trip completed — awaiting operations review'),
      findsWidgets,
    );
    expect(
      find.text('Accra Mall → Kotoka International Airport'),
      findsOneWidget,
    );
    expect(find.text('9.5 km'), findsOneWidget);
    expect(find.text('23 min'), findsOneWidget);
    expect(find.text('Passengers'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(
      find.text(
        'Completion is not confirmed until ALANTEH operations reviews the trip.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back to home'), findsOneWidget);
  });

  testWidgets('accepted ride offer opens Navigate to pickup sequence', (
    tester,
  ) async {
    _useSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: const DriverRideOfferPage(market: MarketConfig.ghanaAccra),
      ),
    );

    await _tapVisible(tester, find.byKey(const Key('view-ride-offer-details')));
    await _tapVisible(
      tester,
      find.byKey(const Key('accept-ride-offer-preview')),
    );

    expect(find.text('Ride accepted'), findsOneWidget);
    expect(find.text('Navigate to pickup'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const Key('navigate-to-pickup-from-accepted')),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('driver-trip-sequence-page')), findsOneWidget);
    expect(find.byKey(const Key('driver-navigate-to-pickup')), findsOneWidget);
  });

  testWidgets(
    'live action disables immediately, ignores rapid taps, and advances only '
    'after confirmation',
    (tester) async {
      _useSurface(tester);
      final queue = _VisualPersistentQueue();
      final gateway = _PendingVisualActionGateway();
      final recorder = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-VISUAL-001',
        driverId: 'DRIVER-VISUAL-001',
      );

      await _pumpTripSequence(tester, actionRecorder: recorder);

      final action = find.byKey(const Key('driver-mark-arrived-pickup'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.tap(action);
      await tester.pump();

      expect(gateway.calls, 1);
      expect(queue.events, hasLength(1));
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      expect(find.text('Confirming...'), findsOneWidget);
      expect(
        find.byKey(const Key('driver-navigate-to-pickup')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driver-arrived-at-pickup')), findsNothing);

      gateway.complete();
      await tester.pumpAndSettle();

      expect(gateway.calls, 1);
      expect(find.byKey(const Key('driver-arrived-at-pickup')), findsOneWidget);
    },
  );

  testWidgets(
    'retryable live action failure never advances and re-enables manual retry',
    (tester) async {
      _useSurface(tester);
      final queue = _VisualPersistentQueue();
      final gateway = _FailingVisualActionGateway();
      final recorder = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-VISUAL-002',
        driverId: 'DRIVER-VISUAL-002',
      );

      await _pumpTripSequence(tester, actionRecorder: recorder);

      final action = find.byKey(const Key('driver-mark-arrived-pickup'));
      await _tapVisible(tester, action);
      await tester.pumpAndSettle();

      expect(gateway.calls, 1);
      expect(queue.events, hasLength(1));
      expect(
        find.byKey(const Key('driver-navigate-to-pickup')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driver-arrived-at-pickup')), findsNothing);
      expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
      expect(
        find.byKey(const Key('driver-trip-action-queued-snackbar')),
        findsOneWidget,
      );
    },
  );

  testWidgets('test_active_trip_uses_authoritative_destination', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTripSequence(tester, initialStatus: 'in_progress');

    expect(find.byKey(const Key('driver-active-trip')), findsOneWidget);
    expect(
      find.text('Heading to Kotoka International Airport'),
      findsOneWidget,
    );
    expect(find.text(_authoritativePickup), findsOneWidget);
    expect(find.text(_authoritativeDestination), findsOneWidget);
    expect(find.text('Accra Market'), findsNothing);
  });

  testWidgets('test_destination_confirmation_uses_authoritative_destination', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTripSequence(tester, initialStatus: 'in_progress');
    await _tapVisible(
      tester,
      find.byKey(const Key('driver-mark-arrived-destination')),
    );

    expect(
      find.text(
        'Confirm the ride has ended safely at '
        'Kotoka International Airport.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Accra Market'), findsNothing);
  });

  testWidgets(
    'test_completion_summary_uses_authoritative_route_and_passenger_count',
    (tester) async {
      _useSurface(tester);

      await _pumpTripSequence(
        tester,
        initialStatus: 'completed_pending_review',
      );

      expect(find.byKey(const Key('driver-trip-completed')), findsOneWidget);
      expect(
        find.text('Accra Mall → Kotoka International Airport'),
        findsOneWidget,
      );
      expect(find.text('Passengers'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Accra Mall → Accra Market'), findsNothing);
      expect(find.text('2'), findsNothing);
    },
  );

  testWidgets('test_resumed_statuses_preserve_authoritative_trip_values', (
    tester,
  ) async {
    _useSurface(tester);

    for (final status in const <String>[
      'driver_accepted',
      'arrived_at_pickup',
      'passenger_onboard',
      'in_progress',
      'completed_pending_review',
    ]) {
      await _pumpTripSequence(tester, initialStatus: status);

      final page = tester.widget<DriverTripVisualSequencePage>(
        find.byType(DriverTripVisualSequencePage),
      );
      expect(page.pickupLocation, _authoritativePickup);
      expect(page.destination, _authoritativeDestination);
      expect(page.passengerCount, _authoritativePassengerCount);

      switch (status) {
        case 'driver_accepted':
          expect(
            find.byKey(const Key('driver-navigate-to-pickup')),
            findsOneWidget,
          );
          expect(find.text(_authoritativePickup), findsWidgets);
          expect(find.text(_authoritativeDestination), findsOneWidget);
        case 'arrived_at_pickup':
          expect(
            find.byKey(const Key('driver-arrived-at-pickup')),
            findsOneWidget,
          );
        case 'passenger_onboard':
          expect(
            find.byKey(const Key('driver-confirm-passenger-onboard')),
            findsOneWidget,
          );
        case 'in_progress':
          expect(find.byKey(const Key('driver-active-trip')), findsOneWidget);
          expect(find.text(_authoritativeDestination), findsOneWidget);
        case 'completed_pending_review':
          expect(
            find.byKey(const Key('driver-trip-completed')),
            findsOneWidget,
          );
          expect(
            find.text('$_authoritativePickup → $_authoritativeDestination'),
            findsOneWidget,
          );
          expect(find.text('1'), findsOneWidget);
      }

      expect(find.text('Accra Market'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('test_missing_trip_values_use_neutral_unavailable_wording', (
    tester,
  ) async {
    _useSurface(tester);

    await _pumpTripSequence(
      tester,
      pickupLocation: '   ',
      destination: '',
      passengerCount: null,
    );

    expect(find.text(driverTripDisplayUnavailable), findsWidgets);
    expect(find.text('Accra Market'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await _pumpTripSequence(
      tester,
      initialStatus: 'completed_pending_review',
      pickupLocation: null,
      destination: '   ',
      passengerCount: null,
    );

    expect(find.text('Not available → Not available'), findsOneWidget);
    expect(find.text(driverTripDisplayUnavailable), findsWidgets);
    expect(find.text('Accra Market'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  test('route fallback exposes stable map coordinates', () {
    final pickup = safeDriverPickupRouteFallback();
    final destination = safeDriverDestinationRouteFallback();

    expect(pickup.usedFallback, isTrue);
    expect(destination.usedFallback, isTrue);
    expect(pickup.points.first, driverPickupStaticPosition);
    expect(destination.points.last, driverDestinationPosition);
  });

  testWidgets(
    'all three trip safety buttons render with non-zero size',
    (tester) async {
      _useSurface(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.driver,
          home: DriverTripVisualSequencePage(
            pickupLocation: _authoritativePickup,
            destination: _authoritativeDestination,
            passengerCount: _authoritativePassengerCount,
            driverTrustedContactRepository: _FakeDriverTrustedContactRepository(),
            driverSafetyAlertRepository: _FakeDriverSafetyAlertRepository(),
          ),
        ),
      );
      await tester.pump();

      for (final key in const [
        'driver-trip-safety-emergency',
        'driver-trip-safety-message-contact',
        'driver-trip-safety-alert-dispatch',
      ]) {
        final finder = find.byKey(Key(key));
        expect(finder, findsOneWidget, reason: key);

        final size = tester.getSize(finder);
        expect(
          size.width,
          greaterThan(0),
          reason: '$key should have a non-zero rendered width',
        );
        expect(
          size.height,
          greaterThan(0),
          reason: '$key should have a non-zero rendered height',
        );
      }
    },
  );

  group('pickup verification code', () {
    testWidgets(
      'code field is absent when the trip does not require verification',
      (tester) async {
        _useSurface(tester);
        final queue = _VisualPersistentQueue();
        final gateway = _PickupCodeGateway();
        final recorder = DriverTripActionResilienceController(
          queue: queue,
          gateway: gateway,
          tripReference: 'TRIP-PVC-001',
          driverId: 'DRIVER-PVC-001',
        );

        await _pumpTripSequence(
          tester,
          actionRecorder: recorder,
          pickupVerificationRequired: false,
        );
        await _tapVisible(
          tester,
          find.byKey(const Key('driver-mark-arrived-pickup')),
        );
        await _tapVisible(
          tester,
          find.byKey(const Key('driver-open-onboard-confirmation')),
        );

        expect(
          find.byKey(const Key('driver-pickup-verification-code-field')),
          findsNothing,
        );

        await _tapVisible(
          tester,
          find.byKey(const Key('driver-confirm-onboard')),
        );

        expect(find.byKey(const Key('driver-active-trip')), findsOneWidget);
        expect(gateway.submittedCodes, [null, null]);
        expect(queue.events, hasLength(2));
      },
    );

    testWidgets('code field appears when the trip requires verification', (
      tester,
    ) async {
      _useSurface(tester);
      final queue = _VisualPersistentQueue();
      final gateway = _PickupCodeGateway();
      final recorder = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-PVC-002',
        driverId: 'DRIVER-PVC-002',
      );

      await _pumpTripSequence(
        tester,
        actionRecorder: recorder,
        pickupVerificationRequired: true,
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-mark-arrived-pickup')),
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-open-onboard-confirmation')),
      );

      expect(
        find.byKey(const Key('driver-pickup-verification-code-field')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Ask your passenger for their pickup code'),
        findsOneWidget,
      );
    });

    testWidgets('an empty code is rejected locally without calling the gateway', (
      tester,
    ) async {
      _useSurface(tester);
      final queue = _VisualPersistentQueue();
      final gateway = _PickupCodeGateway();
      final recorder = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-PVC-003',
        driverId: 'DRIVER-PVC-003',
      );

      await _pumpTripSequence(
        tester,
        actionRecorder: recorder,
        pickupVerificationRequired: true,
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-mark-arrived-pickup')),
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-open-onboard-confirmation')),
      );

      await _tapVisible(
        tester,
        find.byKey(const Key('driver-confirm-onboard')),
      );

      expect(
        find.text('Enter the code your passenger gave you.'),
        findsOneWidget,
      );
      expect(gateway.submittedCodes, [null]);
      expect(
        find.byKey(const Key('driver-confirm-passenger-onboard')),
        findsOneWidget,
      );
    });

    testWidgets('a wrong code shows the server message and stays on this screen', (
      tester,
    ) async {
      _useSurface(tester);
      final queue = _VisualPersistentQueue();
      final gateway = _PickupCodeGateway(correctCode: '1234');
      final recorder = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-PVC-004',
        driverId: 'DRIVER-PVC-004',
      );

      await _pumpTripSequence(
        tester,
        actionRecorder: recorder,
        pickupVerificationRequired: true,
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-mark-arrived-pickup')),
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-open-onboard-confirmation')),
      );

      await tester.enterText(
        find.byKey(const Key('driver-pickup-verification-code-field')),
        '0000',
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-confirm-onboard')),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining("doesn't match"),
        findsOneWidget,
      );
      expect(gateway.submittedCodes, [null, '0000']);
      expect(
        find.byKey(const Key('driver-confirm-passenger-onboard')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('driver-pickup-verification-code-field')),
        findsOneWidget,
      );
      // Pickup verification must never go through the offline queue - it
      // is a live, in-person check, not a deferrable status update. The
      // one queued event here is the earlier arrived-pickup tap, which
      // does use the queue as normal.
      expect(queue.events, hasLength(1));
    });

    testWidgets('the correct code starts the trip', (tester) async {
      _useSurface(tester);
      final queue = _VisualPersistentQueue();
      final gateway = _PickupCodeGateway(correctCode: '1234');
      final recorder = DriverTripActionResilienceController(
        queue: queue,
        gateway: gateway,
        tripReference: 'TRIP-PVC-005',
        driverId: 'DRIVER-PVC-005',
      );

      await _pumpTripSequence(
        tester,
        actionRecorder: recorder,
        pickupVerificationRequired: true,
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-mark-arrived-pickup')),
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-open-onboard-confirmation')),
      );

      await tester.enterText(
        find.byKey(const Key('driver-pickup-verification-code-field')),
        '1234',
      );
      await _tapVisible(
        tester,
        find.byKey(const Key('driver-confirm-onboard')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('driver-active-trip')), findsOneWidget);
      expect(gateway.submittedCodes, [null, '1234']);
      // Only the earlier arrived-pickup tap is queued - the pickup-code
      // submission itself bypasses the offline queue entirely.
      expect(queue.events, hasLength(1));
    });

    testWidgets(
      'three wrong attempts locks the field and points to dispatch escalation',
      (tester) async {
        _useSurface(tester);
        final queue = _VisualPersistentQueue();
        final gateway = _PickupCodeGateway(correctCode: '1234');
        final recorder = DriverTripActionResilienceController(
          queue: queue,
          gateway: gateway,
          tripReference: 'TRIP-PVC-006',
          driverId: 'DRIVER-PVC-006',
        );

        await _pumpTripSequence(
          tester,
          actionRecorder: recorder,
          pickupVerificationRequired: true,
        );
        await _tapVisible(
          tester,
          find.byKey(const Key('driver-mark-arrived-pickup')),
        );
        await _tapVisible(
          tester,
          find.byKey(const Key('driver-open-onboard-confirmation')),
        );

        for (var attempt = 0; attempt < 3; attempt++) {
          await tester.enterText(
            find.byKey(const Key('driver-pickup-verification-code-field')),
            '0000',
          );
          await _tapVisible(
            tester,
            find.byKey(const Key('driver-confirm-onboard')),
          );
          await tester.pumpAndSettle();
        }

        expect(gateway.attempts, 3);
        expect(
          find.byKey(const Key('driver-pickup-verification-code-field')),
          findsNothing,
        );
        expect(find.text('Locked'), findsOneWidget);
        expect(
          find.textContaining('Use the options below to contact dispatch'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('driver-confirm-onboard')),
              )
              .onPressed,
          isNull,
        );
        // The escalation path is the safety bar that's already on this
        // screen, not a new affordance.
        expect(find.text('Emergency 191'), findsOneWidget);
      },
    );

    testWidgets(
      'the code field survives a real on-screen keyboard without overflowing',
      (tester) async {
        _useSurface(tester);
        final queue = _VisualPersistentQueue();
        final gateway = _PickupCodeGateway();
        final recorder = DriverTripActionResilienceController(
          queue: queue,
          gateway: gateway,
          tripReference: 'TRIP-PVC-007',
          driverId: 'DRIVER-PVC-007',
        );

        await _pumpTripSequence(
          tester,
          actionRecorder: recorder,
          pickupVerificationRequired: true,
        );
        await _tapVisible(
          tester,
          find.byKey(const Key('driver-mark-arrived-pickup')),
        );
        await _tapVisible(
          tester,
          find.byKey(const Key('driver-open-onboard-confirmation')),
        );

        tester.view.viewInsets = const FakeViewPadding(bottom: 500);
        addTearDown(() => tester.view.resetViewInsets());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('driver-pickup-verification-code-field')),
          findsOneWidget,
        );
      },
    );
  });
}

final class _FakeDriverTrustedContactRepository
    implements DriverTrustedContactRepository {
  @override
  Future<DriverTrustedContact> fetch() async =>
      const DriverTrustedContact(name: 'Ama Mensah', phone: '+233555000111');

  @override
  Future<DriverTrustedContact> save({
    required String name,
    required String phone,
  }) async => DriverTrustedContact(name: name, phone: phone);
}

final class _FakeDriverSafetyAlertRepository
    implements DriverSafetyAlertRepository {
  @override
  Future<void> send({
    String? tripReference,
    double? latitude,
    double? longitude,
  }) async {}
}

Future<void> _openActiveTrip(WidgetTester tester) async {
  await _pumpTripSequence(tester);

  await _tapVisible(
    tester,
    find.byKey(const Key('driver-mark-arrived-pickup')),
  );
  await _tapVisible(
    tester,
    find.byKey(const Key('driver-open-onboard-confirmation')),
  );
  await _tapVisible(tester, find.byKey(const Key('driver-confirm-onboard')));
}

Future<void> _pumpTripSequence(
  WidgetTester tester, {
  DriverTripActionResilienceController? actionRecorder,
  String? initialStatus,
  String? pickupLocation = _authoritativePickup,
  String? destination = _authoritativeDestination,
  int? passengerCount = _authoritativePassengerCount,
  String? passengerNote,
  bool pickupVerificationRequired = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.driver,
      home: DriverTripVisualSequencePage(
        actionRecorder: actionRecorder,
        initialStatus: initialStatus,
        pickupLocation: pickupLocation,
        destination: destination,
        passengerCount: passengerCount,
        passengerNote: passengerNote,
        pickupVerificationRequired: pickupVerificationRequired,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

final class _VisualPersistentQueue implements DriverTripActionPersistentQueue {
  final events = <QueuedEvent>[];

  @override
  Future<QueuedEvent> enqueue(QueuedEvent event) async {
    final index = events.indexWhere((candidate) => candidate.id == event.id);
    if (index < 0) {
      events.add(event);
    } else {
      events[index] = event;
    }
    return event;
  }

  @override
  Future<QueuedEvent?> eventById(String id) async {
    for (final event in events) {
      if (event.id == id) {
        return event;
      }
    }
    return null;
  }

  @override
  Future<List<QueuedEvent>> pendingEvents() async {
    return events
        .where(
          (event) =>
              event.syncStatus == QueueSyncStatus.pending ||
              event.syncStatus == QueueSyncStatus.failed,
        )
        .toList(growable: false);
  }

  @override
  Future<void> markFailed(String id) async {}

  @override
  Future<void> markPermanentlyFailed(String id) async {}

  @override
  Future<void> markSynced(String id) async {
    final event = await eventById(id);
    if (event == null) {
      return;
    }
    await enqueue(event.copyWith(syncStatus: QueueSyncStatus.synced));
  }
}

final class _PendingVisualActionGateway implements DriverTripActionGateway {
  final _completer = Completer<DriverTripActionReceipt>();
  int calls = 0;

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
    String? pickupVerificationCode,
  }) {
    calls += 1;
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      const DriverTripActionReceipt(
        tripReference: 'TRIP-VISUAL-001',
        status: 'arrived_at_pickup',
        message: 'Arrival confirmed.',
        duplicate: false,
      ),
    );
  }
}

final class _FailingVisualActionGateway implements DriverTripActionGateway {
  int calls = 0;

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
    String? pickupVerificationCode,
  }) async {
    calls += 1;
    throw const DriverTripActionException(
      type: DriverTripActionFailureType.temporarilyUnavailable,
      message: 'Cannot confirm this action right now.',
    );
  }
}

final class _PickupCodeGateway implements DriverTripActionGateway {
  _PickupCodeGateway({this.correctCode = '1234'});

  final String correctCode;
  final List<String?> submittedCodes = [];
  final List<String> idempotencyKeys = [];
  int attempts = 0;

  @override
  Future<DriverTripActionReceipt> submit({
    required DriverTripAction action,
    required String tripReference,
    required String idempotencyKey,
    Map<String, Object?> body = const <String, Object?>{},
    String? pickupVerificationCode,
  }) async {
    submittedCodes.add(pickupVerificationCode);
    idempotencyKeys.add(idempotencyKey);

    if (action != DriverTripAction.startTrip || pickupVerificationCode == null) {
      // A null code means either a different action, or (for start-trip)
      // the generic un-coded path a trip with verification switched off
      // uses - both always succeed here, mirroring the real backend
      // only enforcing when a code is actually present server-side.
      return DriverTripActionReceipt(
        tripReference: tripReference,
        status: action.expectedStatus,
        message: 'Confirmed.',
        duplicate: false,
      );
    }

    if (pickupVerificationCode == correctCode) {
      return DriverTripActionReceipt(
        tripReference: tripReference,
        status: action.expectedStatus,
        message: 'Trip started.',
        duplicate: false,
      );
    }

    attempts += 1;
    if (attempts >= 3) {
      throw DriverTripActionException(
        type: DriverTripActionFailureType.pickupCodeLocked,
        message:
            'Too many incorrect pickup code attempts. Contact dispatch to '
            'continue this trip.',
        attemptsRemaining: 0,
      );
    }

    throw DriverTripActionException(
      type: DriverTripActionFailureType.pickupCodeMismatch,
      message:
          "That pickup code doesn't match. Ask your passenger to confirm "
          'it and try again.',
      attemptsRemaining: 3 - attempts,
    );
  }
}

void _useSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1000);

  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
