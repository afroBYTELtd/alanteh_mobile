import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:asm_maps/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:passenger_app/booking/booking_submission.dart';
import 'package:passenger_app/location/location_search_page.dart';
import 'package:passenger_app/location/passenger_landmarks.dart';
import 'package:passenger_app/location/passenger_places.dart';
import 'package:passenger_app/location/pickup_source.dart';
import 'package:passenger_app/passenger_home.dart';
import 'package:passenger_app/passenger_shell.dart';

// Google Maps step 2 (mobile): place search for the pickup. Search must
// never block booking, never pick a place on its own, and the booking
// must say honestly how the pin got where it is.
const _osu = LatLng(5.5560, -0.1820);
const _accraMall = LatLng(5.6227, -0.1737);
const _dragged = LatLng(5.6130, -0.1730);

const _accraMallSuggestion = PassengerPlaceSuggestion(
  placeId: 'ChIJ_accra_mall',
  mainText: 'Accra Mall',
  secondaryText: 'Tetteh Quarshie, Accra',
);
const _osuSuggestion = PassengerPlaceSuggestion(
  placeId: 'ChIJ_osu_castle',
  mainText: 'Osu Castle',
  secondaryText: 'Osu, Accra',
);
// Picking a suggestion brings back the place and the passenger's own
// words - never the suggestion's (Google's) text.
const _accraMallPlace = PassengerPickedPlace(
  placeId: 'ChIJ_accra_mall',
  coordinates: _accraMall,
  typedText: 'Accra',
);

void main() {
  group('search page', () {
    testWidgets('suggestions come after typing pauses, in one session', (
      tester,
    ) async {
      final places = _FakePlaces();
      await _pumpSearch(tester, places: places);

      await tester.enterText(_field(), 'Ac');
      await tester.pump(const Duration(milliseconds: 299));
      expect(places.autocompleteCalls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(places.autocompleteCalls, hasLength(1));
      expect(places.autocompleteCalls.single.input, 'Ac');
      expect(find.text('Accra Mall'), findsOneWidget);
      expect(find.text('Tetteh Quarshie, Accra'), findsOneWidget);

      await tester.enterText(_field(), 'Acc');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(_field(), 'Accra');
      await tester.pump(passengerPlacesSearchDebounce);
      await tester.pump();

      expect(places.autocompleteCalls.map((call) => call.input), [
        'Ac',
        'Accra',
      ]);
      expect(
        places.autocompleteCalls.map((call) => call.sessionToken).toSet(),
        {'token-1'},
      );
    });

    testWidgets('one character never searches', (tester) async {
      final places = _FakePlaces();
      await _pumpSearch(tester, places: places);

      await tester.enterText(_field(), 'A');
      await tester.pump(const Duration(seconds: 1));

      expect(places.autocompleteCalls, isEmpty);
    });

    testWidgets(
      'picking a suggestion closes the session with Details on the same '
      'token and returns the place',
      (tester) async {
        final places = _FakePlaces();
        final result = await _pumpSearchHarness(tester, places: places);

        await _search(tester, 'Accra');
        await tester.tap(find.byKey(const ValueKey('place-suggestion-0')));
        await tester.pumpAndSettle();

        expect(places.detailsCalls, hasLength(1));
        expect(places.detailsCalls.single.placeId, 'ChIJ_accra_mall');
        expect(places.detailsCalls.single.sessionToken, 'token-1');
        final picked = result.value as PassengerPickedPlace;
        expect(picked.placeId, 'ChIJ_accra_mall');
        expect(picked.coordinates, _accraMall);
        expect(picked.typedText, 'Accra');
      },
    );

    testWidgets('Enter never picks the top suggestion', (tester) async {
      final places = _FakePlaces();
      final result = await _pumpSearchHarness(tester, places: places);

      await _search(tester, 'Accra');
      expect(find.text('Accra Mall'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(places.detailsCalls, isEmpty);
      expect(result.value, 'Accra');
    });

    testWidgets('a second tap while Details runs closes the session once', (
      tester,
    ) async {
      final places = _FakePlaces()..holdDetails = true;
      await _pumpSearchHarness(tester, places: places);

      await _search(tester, 'Accra');
      await tester.tap(find.byKey(const ValueKey('place-suggestion-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('place-suggestion-1')));
      await tester.pump();

      expect(places.detailsCalls, hasLength(1));
    });

    testWidgets(
      'when search is unavailable it says so, stops calling, and typed '
      'text still works',
      (tester) async {
        final places = _FakePlaces()..autocompleteFails = true;
        final result = await _pumpSearchHarness(tester, places: places);

        await _search(tester, 'Accra');
        expect(
          find.byKey(const Key('place-search-unavailable')),
          findsOneWidget,
        );

        await _search(tester, 'Accra Mall');
        expect(places.autocompleteCalls, hasLength(1));

        await tester.tap(find.byKey(const Key('use-location-description')));
        await tester.pumpAndSettle();
        expect(result.value, 'Accra Mall');
      },
    );

    testWidgets('a failed Details keeps the page and retries on the same '
        'token', (tester) async {
      final places = _FakePlaces()..detailsFailures = 1;
      final result = await _pumpSearchHarness(tester, places: places);

      await _search(tester, 'Accra');
      await tester.tap(find.byKey(const ValueKey('place-suggestion-0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('place-details-failed')), findsOneWidget);
      expect(result.value, isNull);

      await tester.tap(find.byKey(const ValueKey('place-suggestion-0')));
      await tester.pumpAndSettle();

      expect(places.detailsCalls.map((call) => call.sessionToken), [
        'token-1',
        'token-1',
      ]);
      expect(result.value, isA<PassengerPickedPlace>());
    });

    testWidgets('an older answer arriving late is dropped', (tester) async {
      final places = _FakePlaces()..holdAutocomplete = true;
      await _pumpSearch(tester, places: places);

      await tester.enterText(_field(), 'Os');
      await tester.pump(passengerPlacesSearchDebounce);
      await tester.enterText(_field(), 'Accra');
      await tester.pump(passengerPlacesSearchDebounce);

      places.answerAutocomplete(1, const [_accraMallSuggestion]);
      await tester.pump();
      places.answerAutocomplete(0, const [_osuSuggestion]);
      await tester.pump();

      expect(find.text('Accra Mall'), findsOneWidget);
      expect(find.text('Osu Castle'), findsNothing);
    });

    testWidgets('each search page has its own session; leaving closes none', (
      tester,
    ) async {
      final places = _FakePlaces();
      await _pumpSearchHarness(tester, places: places);
      await _search(tester, 'Accra');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open pickup search'));
      await tester.pumpAndSettle();
      await _search(tester, 'Osu');

      expect(places.autocompleteCalls.map((call) => call.sessionToken), [
        'token-1',
        'token-2',
      ]);
      expect(places.detailsCalls, isEmpty);
    });

    testWidgets('the Google Maps logo shows with the suggestions, 16 to 19 '
        'dp tall', (tester) async {
      await _pumpSearch(tester, places: _FakePlaces());
      expect(
        find.byKey(const Key('place-search-google-maps-logo')),
        findsNothing,
      );

      await _search(tester, 'Accra');

      final logo = find.byKey(const Key('place-search-google-maps-logo'));
      expect(logo, findsOneWidget);
      final image = tester.widget<Image>(logo);
      expect(
        (image.image as AssetImage).assetName,
        'assets/google_maps/google_maps_logo_gray.png',
      );
      final height = tester.getSize(logo).height;
      expect(height, greaterThanOrEqualTo(16));
      expect(height, lessThanOrEqualTo(19));
      // Inside the suggestions' own container, with the results.
      expect(
        find.descendant(
          of: find.byKey(const Key('place-suggestions-panel')),
          matching: logo,
        ),
        findsOneWidget,
      );
    });

    testWidgets('Google content sits apart from our own', (tester) async {
      var tokens = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AsmThemes.passenger,
          home: LocationSearchPage(
            kind: LocationSearchKind.pickup,
            placesRepository: _FakePlaces(),
            sessionTokenFactory: () => 'token-${++tokens}',
            recentDescriptions: const ['Gate 2'],
          ),
        ),
      );
      await _search(tester, 'Accra');

      final panel = find.byKey(const Key('place-suggestions-panel'));
      // A bordered panel of its own: neither the passenger's typed-text
      // button nor their recent places are inside it.
      final decorated = tester.widget<Container>(panel);
      expect((decorated.decoration! as BoxDecoration).border, isNotNull);
      expect(
        find.descendant(
          of: panel,
          matching: find.byKey(const Key('use-location-description')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.byKey(const ValueKey('recent-location-0')),
        ),
        findsNothing,
      );
      final logoBox = tester.getRect(
        find.byKey(const Key('place-search-google-maps-logo')),
      );
      final panelBox = tester.getRect(panel);
      // Clear space: at least 10 dp to the panel's sides and top of the logo,
      // 5 dp below.
      expect(logoBox.left - panelBox.left, greaterThanOrEqualTo(10));
      expect(logoBox.bottom, lessThanOrEqualTo(panelBox.bottom - 5));
    });

    testWidgets('destination search never calls place search', (tester) async {
      final places = _FakePlaces();
      await _pumpSearch(
        tester,
        places: places,
        kind: LocationSearchKind.destination,
      );

      await _search(tester, 'Accra');

      expect(places.autocompleteCalls, isEmpty);
      expect(find.byKey(const ValueKey('place-suggestion-0')), findsNothing);
    });
  });

  group('pin source', () {
    testWidgets(
      'GPS only: recenter then confirm gives gps and no place, with no '
      'search and no drag',
      (tester) async {
        final location = _ScriptedLocation();
        final selections = <PassengerPickupSelection>[];
        await _pumpHome(
          tester,
          location: location,
          onConfirmPickup: selections.add,
        );

        await _tapRecenter(tester);
        location.answer(0, _fix(_osu));
        location.fail(1, PassengerLocationFailure.timedOut);
        await tester.pump();
        await tester.pump(asmFakeMapAnimationDuration);
        await tester.pump();

        await tester.tap(find.byKey(const Key('confirm-pickup')));
        await tester.pump();

        expect(selections.single.coordinates, _osu);
        expect(selections.single.source, PassengerPickupSource.gps);
        expect(selections.single.placeId, isNull);
      },
    );

    testWidgets(
      'a picked place moves the pin, is named from our own data, and still '
      'waits for Confirm',
      (tester) async {
        final geocoder = _RecordingGeocoder();
        final selections = <PassengerPickupSelection>[];
        await _pumpHome(
          tester,
          location: _ScriptedLocation(),
          geocoder: geocoder,
          onOpenPickupSearch: (_) async => _accraMallPlace,
          onConfirmPickup: selections.add,
        );

        await tester.tap(
          find.byKey(const Key('passenger-home-pickup-address-row')),
        );
        await tester.pump();
        await tester.pump(asmFakeMapAnimationDuration);
        await tester.pump(const Duration(seconds: 1));

        expect(_map(tester).camera.center, _accraMall);
        expect(
          find.byKey(const Key('passenger-home-pickup-address-text')),
          findsOneWidget,
        );
        // Google's EEA terms: no Google text beside the map.
        expect(find.text('Accra Mall'), findsNothing);
        expect(find.text('Near the pin'), findsOneWidget);
        expect(geocoder.calls, contains(_accraMall));
        expect(selections, isEmpty);

        await tester.tap(find.byKey(const Key('confirm-pickup')));
        await tester.pump();

        expect(selections.single.coordinates, _accraMall);
        expect(selections.single.source, PassengerPickupSource.search);
        expect(selections.single.placeId, 'ChIJ_accra_mall');
        expect(selections.single.address, 'Near the pin');
        expect(selections.single.ownWords, 'Accra');
      },
    );

    testWidgets('with no landmark near, a picked place is named in the '
        "passenger's own words", (tester) async {
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: _ScriptedLocation(),
        geocoder: const _NoLandmarkGeocoder(),
        onOpenPickupSearch: (_) async => _accraMallPlace,
        onConfirmPickup: selections.add,
      );

      await tester.tap(
        find.byKey(const Key('passenger-home-pickup-address-row')),
      );
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Accra'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();
      expect(selections.single.address, 'Accra');
    });

    testWidgets('with no landmark and no words, a pin is a Pinned location', (
      tester,
    ) async {
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: _ScriptedLocation(),
        geocoder: const _NoLandmarkGeocoder(),
        onConfirmPickup: selections.add,
      );

      _map(tester)
        ..dragTo(_dragged)
        ..release();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Pinned location'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();
      expect(selections.single.address, 'Pinned location');
      expect(selections.single.ownWords, isNull);
    });

    testWidgets('dragging after a search is dragged and drops the place', (
      tester,
    ) async {
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: _ScriptedLocation(),
        onOpenPickupSearch: (_) async => _accraMallPlace,
        onConfirmPickup: selections.add,
      );

      await tester.tap(
        find.byKey(const Key('passenger-home-pickup-address-row')),
      );
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);
      _map(tester)
        ..dragTo(_dragged)
        ..release();
      await tester.pump();

      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();

      expect(selections.single.coordinates, _dragged);
      expect(selections.single.source, PassengerPickupSource.dragged);
      expect(selections.single.placeId, isNull);
    });

    testWidgets('a drag that stops the move to a place is dragged', (
      tester,
    ) async {
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: _ScriptedLocation(),
        onOpenPickupSearch: (_) async => _accraMallPlace,
        onConfirmPickup: selections.add,
      );

      await tester.tap(
        find.byKey(const Key('passenger-home-pickup-address-row')),
      );
      await tester.pump();
      // A finger takes the map before the move reaches the place.
      _map(tester)
        ..dragTo(_dragged)
        ..release();
      await tester.pump();

      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();
      // The stand-in map finishes its animation; let it.
      await tester.pump(asmFakeMapAnimationDuration);

      expect(selections.single.coordinates, _dragged);
      expect(selections.single.source, PassengerPickupSource.dragged);
      expect(selections.single.placeId, isNull);
    });

    testWidgets('dragging after a recenter is dragged', (tester) async {
      final location = _ScriptedLocation();
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: location,
        onConfirmPickup: selections.add,
      );

      await _tapRecenter(tester);
      location.answer(0, _fix(_osu));
      location.fail(1, PassengerLocationFailure.timedOut);
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);
      _map(tester)
        ..dragTo(_dragged)
        ..release();
      await tester.pump();

      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();

      expect(selections.single.source, PassengerPickupSource.dragged);
    });

    testWidgets('a move that leaves the pin in place keeps the search', (
      tester,
    ) async {
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: _ScriptedLocation(),
        onOpenPickupSearch: (_) async => _accraMallPlace,
        onConfirmPickup: selections.add,
      );

      await tester.tap(
        find.byKey(const Key('passenger-home-pickup-address-row')),
      );
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);
      // A pinch-zoom: the camera moves and stops where it was.
      _map(tester)
        ..dragTo(_accraMall)
        ..release();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Near the pin'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();

      expect(selections.single.source, PassengerPickupSource.search);
      expect(selections.single.placeId, 'ChIJ_accra_mall');
    });

    testWidgets('a place already under the pin is placed at once', (
      tester,
    ) async {
      // The map may report no move at all when sent where it already is.
      const underThePin = PassengerPickedPlace(
        placeId: 'ChIJ_under_the_pin',
        coordinates: passengerHomePickupDefaultCenter,
        typedText: 'Under the pin',
      );
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: _ScriptedLocation(),
        onOpenPickupSearch: (_) async => underThePin,
        onConfirmPickup: selections.add,
      );

      await tester.tap(
        find.byKey(const Key('passenger-home-pickup-address-row')),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();
      expect(selections.single.source, PassengerPickupSource.search);
      expect(selections.single.placeId, 'ChIJ_under_the_pin');
    });

    testWidgets('the untouched starting point cannot be confirmed', (
      tester,
    ) async {
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: _ScriptedLocation(),
        onConfirmPickup: selections.add,
      );
      await tester.pump(const Duration(seconds: 1));

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-pickup')))
            .onPressed,
        isNull,
      );
      expect(
        find.byKey(const Key('passenger-home-pickup-hint')),
        findsOneWidget,
      );

      _map(tester)
        ..dragTo(_dragged)
        ..release();
      await tester.pump();

      expect(find.byKey(const Key('passenger-home-pickup-hint')), findsNothing);
      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();
      expect(selections.single.source, PassengerPickupSource.dragged);
    });

    testWidgets('the hint is clear of the header, the pin and the sheet', (
      tester,
    ) async {
      // Seen on the Android test phone: above the pin, the hint sat under
      // the solar banner.
      tester.view.physicalSize = const Size(1080, 2070);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 72);
      addTearDown(tester.view.reset);
      await _pumpHome(tester, location: _ScriptedLocation());
      await tester.pump(const Duration(seconds: 1));

      final hint = tester.getRect(
        find.byKey(const Key('passenger-home-pickup-hint')),
      );
      final header = tester.getRect(
        find.byKey(const Key('passenger-home-safe-top-content')),
      );
      final pin = tester.getRect(
        find.byKey(const Key('passenger-home-centre-pin')),
      );
      final sheet = tester.getRect(
        find.byKey(const Key('passenger-home-bottom-sheet')),
      );
      expect(hint.overlaps(header), isFalse, reason: '$hint vs $header');
      expect(hint.overlaps(pin), isFalse, reason: '$hint vs $pin');
      expect(hint.overlaps(sheet), isFalse, reason: '$hint vs $sheet');
    });

    testWidgets('typed text after a search forgets the place', (tester) async {
      Object? nextResult = _accraMallPlace;
      final selections = <PassengerPickupSelection>[];
      await _pumpHome(
        tester,
        location: _ScriptedLocation(),
        onOpenPickupSearch: (_) async => nextResult,
        onConfirmPickup: selections.add,
      );

      await tester.tap(
        find.byKey(const Key('passenger-home-pickup-address-row')),
      );
      await tester.pump();
      await tester.pump(asmFakeMapAnimationDuration);

      nextResult = 'Gate 2';
      await tester.tap(
        find.byKey(const Key('passenger-home-pickup-address-row')),
      );
      await tester.pump();
      // The pin has not moved, but the passenger has to place it again.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-pickup')))
            .onPressed,
        isNull,
      );

      // A move that ends where the place was still is not the place.
      _map(tester)
        ..dragTo(_accraMall)
        ..release();
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pump();

      expect(selections.single.source, PassengerPickupSource.dragged);
      expect(selections.single.placeId, isNull);
    });
  });

  group('what the booking sends', () {
    testWidgets(
      'GPS only, end to end: pickup_source gps and no pickup_place_id',
      (tester) async {
        final client = _RecordingApiClient();
        final location = _ScriptedLocation();
        await _pumpShell(tester, client: client, location: location);

        await _tapRecenter(tester);
        location.answer(0, _fix(_osu));
        location.fail(1, PassengerLocationFailure.timedOut);
        await tester.pump();
        await tester.pump(asmFakeMapAnimationDuration);
        await tester.pump();

        await _bookFromHome(tester);

        final body = client.lastSubmission!.toJson();
        expect(body['pickup_latitude'], _osu.latitude);
        expect(body['pickup_longitude'], _osu.longitude);
        expect(body['pickup_source'], 'gps');
        expect(body.containsKey('pickup_place_id'), isFalse);
        expect(body['destination'], 'Airport');
        expect(body.keys, isNot(contains('destination_latitude')));
      },
    );

    testWidgets('search, end to end: pickup_source search and the place id', (
      tester,
    ) async {
      final client = _RecordingApiClient();
      final places = _FakePlaces();
      await _pumpShell(
        tester,
        client: client,
        location: _ScriptedLocation(),
        places: places,
      );

      await tester.tap(
        find.byKey(const Key('passenger-home-pickup-address-row')),
      );
      await tester.pumpAndSettle();
      await _search(tester, 'Accra');
      await tester.tap(find.byKey(const ValueKey('place-suggestion-0')));
      await tester.pumpAndSettle();

      await _bookFromHome(tester);

      final body = client.lastSubmission!.toJson();
      expect(body['pickup_latitude'], _accraMall.latitude);
      expect(body['pickup_longitude'], _accraMall.longitude);
      expect(body['pickup_source'], 'search');
      expect(body['pickup_place_id'], 'ChIJ_accra_mall');
      // The passenger's own words, never the suggestion text.
      expect(body['pickup_location'], 'Accra');
      expect(body.values.join(' '), isNot(contains('Tetteh')));
    });

    testWidgets(
      'the booking page asks the passenger to name the place, starting from '
      'their own words',
      (tester) async {
        await _pumpShell(
          tester,
          client: _RecordingApiClient(),
          location: _ScriptedLocation(),
          places: _FakePlaces(),
        );

        await tester.tap(
          find.byKey(const Key('passenger-home-pickup-address-row')),
        );
        await tester.pumpAndSettle();
        await _search(tester, 'Accra');
        await tester.tap(find.byKey(const ValueKey('place-suggestion-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-pickup')));
        await tester.pumpAndSettle();

        expect(find.text('Name this place for your driver'), findsOneWidget);
        final field = tester.widget<TextFormField>(
          find.byKey(const Key('booking-pickup')),
        );
        expect(field.controller!.text, 'Accra');
      },
    );

    testWidgets('with no words, the booking page starts from the pin label', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        client: _RecordingApiClient(),
        location: _ScriptedLocation(),
      );

      _map(tester)
        ..dragTo(_dragged)
        ..release();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('confirm-pickup')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('booking-pickup')),
      );
      expect(field.controller!.text, 'Near the pin');
    });

    testWidgets('dragged, end to end: pickup_source dragged and no place', (
      tester,
    ) async {
      final client = _RecordingApiClient();
      await _pumpShell(tester, client: client, location: _ScriptedLocation());

      _map(tester)
        ..dragTo(_dragged)
        ..release();
      await tester.pump();

      await _bookFromHome(tester);

      final body = client.lastSubmission!.toJson();
      expect(body['pickup_source'], 'dragged');
      expect(body.containsKey('pickup_place_id'), isFalse);
    });
  });
}

Finder _field() => find.byKey(const Key('location-description'));

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(_field(), text);
  await tester.pump(passengerPlacesSearchDebounce);
  await tester.pump();
}

Future<void> _pumpSearch(
  WidgetTester tester, {
  required _FakePlaces places,
  LocationSearchKind kind = LocationSearchKind.pickup,
}) async {
  var tokens = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: LocationSearchPage(
        kind: kind,
        placesRepository: places,
        sessionTokenFactory: () => 'token-${++tokens}',
      ),
    ),
  );
  await tester.pump();
}

final class _Result {
  Object? value;
}

Future<_Result> _pumpSearchHarness(
  WidgetTester tester, {
  required _FakePlaces places,
}) async {
  final result = _Result();
  var tokens = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                result.value = await Navigator.of(context).push<Object>(
                  MaterialPageRoute<Object>(
                    builder: (_) => LocationSearchPage(
                      kind: LocationSearchKind.pickup,
                      placesRepository: places,
                      sessionTokenFactory: () => 'token-${++tokens}',
                    ),
                  ),
                );
              },
              child: const Text('Open pickup search'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open pickup search'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required _ScriptedLocation location,
  PassengerHomeReverseGeocoder geocoder = const _NamedGeocoder(),
  ValueChanged<PassengerPickupSelection>? onConfirmPickup,
  PassengerHomePickupSearch? onOpenPickupSearch,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: Scaffold(
        body: PassengerHome(
          market: AsmAppConfig.localGhana.market,
          localQaEnabled: true,
          pickupDescription: null,
          destinationDescription: null,
          canContinue: false,
          locationsMatch: false,
          canSwap: false,
          hasRoute: false,
          onChoosePickup: () {},
          onChooseDestination: () {},
          onContinue: () {},
          onOpenRequests: () {},
          onSwap: () {},
          onClear: () {},
          onOpenPickupSearch: onOpenPickupSearch ?? (_) async => null,
          onConfirmPickup: onConfirmPickup ?? (_) {},
          reverseGeocoder: geocoder,
          deviceLocationService: location,
          locationPermissionService: const _Granted(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required _RecordingApiClient client,
  required _ScriptedLocation location,
  _FakePlaces? places,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AsmThemes.passenger,
      home: PassengerShell(
        configuration: AsmAppConfig.localGhana,
        localQaEnabled: true,
        rideRequestSubmitter: ApiPassengerRideRequestSubmitter(
          client,
          connectionConfigured: true,
        ),
        placesRepository: places,
        homeReverseGeocoder: const _NamedGeocoder(),
        homeDeviceLocationService: location,
        homeLocationPermissionService: const _Granted(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Confirms the pickup on the map and books it to the airport.
Future<void> _bookFromHome(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('confirm-pickup')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('booking-destination')),
    'Airport',
  );
  await _tapVisible(tester, const Key('request-ride'));
  await tester.pumpAndSettle();
  await _tapVisible(tester, const Key('confirm-and-request'));
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  for (var attempt = 0; attempt < 15; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      break;
    }
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 120));
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
}

AsmFakeMapState _map(WidgetTester tester) {
  return tester.state<AsmFakeMapState>(find.byType(AsmFakeMap));
}

Future<void> _tapRecenter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('passenger-home-recenter')));
  await tester.pump();
  await tester.pump();
}

PassengerDevicePosition _fix(LatLng at) {
  return PassengerDevicePosition(
    coordinates: at,
    accuracyMetres: 60,
    timestamp: DateTime.now(),
  );
}

final class _FakePlaces implements PassengerPlacesRepository {
  final autocompleteCalls = <({String input, String sessionToken})>[];
  final detailsCalls = <({String placeId, String sessionToken})>[];
  final _heldAutocomplete = <Completer<List<PassengerPlaceSuggestion>>>[];
  bool autocompleteFails = false;
  bool holdAutocomplete = false;
  bool holdDetails = false;
  int detailsFailures = 0;

  static const _places = {
    'ChIJ_accra_mall': _accraMall,
    'ChIJ_osu_castle': _osu,
  };

  @override
  Future<List<PassengerPlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  }) {
    autocompleteCalls.add((input: input, sessionToken: sessionToken));
    if (autocompleteFails) {
      return Future.error(const PassengerPlacesUnavailableException());
    }
    if (holdAutocomplete) {
      final answer = Completer<List<PassengerPlaceSuggestion>>();
      _heldAutocomplete.add(answer);
      return answer.future;
    }
    return Future.value(const [_accraMallSuggestion, _osuSuggestion]);
  }

  void answerAutocomplete(int call, List<PassengerPlaceSuggestion> answer) {
    _heldAutocomplete[call].complete(answer);
  }

  @override
  Future<PassengerPlaceLocation> details(
    String placeId, {
    required String sessionToken,
  }) {
    detailsCalls.add((placeId: placeId, sessionToken: sessionToken));
    if (holdDetails) {
      return Completer<PassengerPlaceLocation>().future;
    }
    if (detailsFailures > 0) {
      detailsFailures -= 1;
      return Future.error(const PassengerPlacesUnavailableException());
    }
    return Future.value(
      PassengerPlaceLocation(placeId: placeId, coordinates: _places[placeId]!),
    );
  }
}

class _ScriptedLocation implements PassengerHomeDeviceLocationService {
  final _answers = <Completer<PassengerDevicePosition>>[];

  @override
  Future<PassengerDevicePosition?> lastKnownPosition() async => null;

  @override
  Future<PassengerDevicePosition> currentPosition({
    required bool precise,
    required Duration timeLimit,
  }) {
    final answer = Completer<PassengerDevicePosition>();
    _answers.add(answer);
    return answer.future;
  }

  @override
  Stream<PassengerDevicePosition> get positionStream =>
      StreamController<PassengerDevicePosition>().stream;

  void answer(int request, PassengerDevicePosition position) =>
      _answers[request].complete(position);

  void fail(int request, PassengerLocationFailure failure) =>
      _answers[request].completeError(PassengerLocationException(failure));
}

class _Granted implements PassengerHomeLocationPermissionService {
  const _Granted();

  @override
  Future<PassengerHomeLocationPermissionState> ensurePermission() async =>
      PassengerHomeLocationPermissionState.granted;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _NoLandmarkGeocoder implements PassengerHomeReverseGeocoder {
  const _NoLandmarkGeocoder();

  @override
  Future<String> reverseGeocode(LatLng coordinates) async =>
      throw const NoLandmarkNearbyException();
}

class _NamedGeocoder implements PassengerHomeReverseGeocoder {
  const _NamedGeocoder();

  @override
  Future<String> reverseGeocode(LatLng coordinates) async => 'Near the pin';
}

class _RecordingGeocoder implements PassengerHomeReverseGeocoder {
  final calls = <LatLng>[];

  @override
  Future<String> reverseGeocode(LatLng coordinates) async {
    calls.add(coordinates);
    return 'Near the pin';
  }
}

class _RecordingApiClient extends AsmApiClient {
  _RecordingApiClient() : super(baseUrl: 'https://control.example/api/');

  PassengerRideRequestSubmission? lastSubmission;

  @override
  Future<ApiResponse<PassengerRideRequestResult>> submitPassengerRideRequest(
    PassengerRideRequestSubmission submission,
  ) async {
    lastSubmission = submission;
    return ApiResponse.success(
      const PassengerRideRequestResult(
        requestReference: 'RR-APP-3A9F1C2B4E5D',
        status: 'requested',
        message: 'Your ride request was received.',
      ),
      statusCode: 201,
    );
  }
}
