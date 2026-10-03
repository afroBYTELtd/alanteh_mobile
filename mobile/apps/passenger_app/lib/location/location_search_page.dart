import 'dart:async';

import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'passenger_places.dart';

enum LocationSearchKind { pickup, destination }

extension LocationSearchKindLabel on LocationSearchKind {
  String get title => switch (this) {
    LocationSearchKind.pickup => 'Where are you?',
    LocationSearchKind.destination => 'Where to?',
  };

  String get fieldLabel => switch (this) {
    LocationSearchKind.pickup => 'Your pickup location',
    LocationSearchKind.destination => 'Your destination',
  };
}

class LocationSearchPage extends StatefulWidget {
  const LocationSearchPage({
    required this.kind,
    this.market = MarketConfig.ghanaAccra,
    this.initialDescription,
    this.recentDescriptions = const [],
    this.placesRepository,
    this.sessionTokenFactory = newPlacesSessionToken,
    super.key,
  });

  final LocationSearchKind kind;
  final MarketConfig market;
  final String? initialDescription;
  final List<String> recentDescriptions;

  /// Suggests places for a pickup search, which then returns a
  /// [PassengerPickedPlace]. Typed text always returns a `String`.
  /// Destination search never uses it: destinations have no coordinates
  /// on the server yet.
  final PassengerPlacesRepository? placesRepository;

  /// A session token per page: one search, closed by one Details call.
  final String Function() sessionTokenFactory;

  @override
  State<LocationSearchPage> createState() => _LocationSearchPageState();
}

class _LocationSearchPageState extends State<LocationSearchPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  PassengerPlacesRepository? _places;
  late final String _sessionToken;
  Timer? _searchTimer;
  int _searchGeneration = 0;
  List<PassengerPlaceSuggestion> _suggestions = const [];
  bool _searchUnavailable = false;
  bool _detailsFailed = false;
  String? _resolvingPlaceId;

  @override
  void initState() {
    super.initState();
    final initialText = widget.initialDescription ?? '';
    _controller = TextEditingController(text: initialText);
    if (widget.kind == LocationSearchKind.pickup) {
      _places = widget.placesRepository;
    }
    if (_places != null) {
      _sessionToken = widget.sessionTokenFactory();
      // Typing replaces the current address rather than adding to it.
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialText.length,
      );
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchGeneration++;
    _controller.dispose();
    super.dispose();
  }

  void _handleTextChanged(String text) {
    final places = _places;
    if (places == null || _searchUnavailable) {
      return;
    }
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    final input = text.trim();
    if (input.length < passengerPlacesMinimumInput ||
        input.length > passengerPlacesMaximumInput) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = const []);
      }
      return;
    }
    _searchTimer = Timer(passengerPlacesSearchDebounce, () async {
      try {
        final suggestions = await places.autocomplete(
          input,
          sessionToken: _sessionToken,
        );
        if (mounted && generation == _searchGeneration) {
          setState(() => _suggestions = suggestions);
        }
      } on Object {
        // Unavailable for this search: say so once and stop asking.
        if (mounted && generation == _searchGeneration) {
          setState(() {
            _searchUnavailable = true;
            _suggestions = const [];
          });
        }
      }
    });
  }

  Future<void> _pickSuggestion(PassengerPlaceSuggestion suggestion) async {
    final places = _places;
    // One Details call ends the session; a second tap must not repeat it.
    if (places == null || _resolvingPlaceId != null) {
      return;
    }
    _searchTimer?.cancel();
    _searchGeneration++;
    setState(() {
      _resolvingPlaceId = suggestion.placeId;
      _detailsFailed = false;
    });
    try {
      final location = await places.details(
        suggestion.placeId,
        sessionToken: _sessionToken,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        PassengerPickedPlace(
          placeId: location.placeId,
          coordinates: location.coordinates,
          mainText: suggestion.mainText,
          secondaryText: suggestion.secondaryText,
        ),
      );
    } on Object {
      // The session stays open, so tapping again retries on the same token.
      if (mounted) {
        setState(() {
          _resolvingPlaceId = null;
          _detailsFailed = true;
        });
      }
    }
  }

  void _useDescription() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.kind.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AsmSpacing.space20),
          children: [
            Semantics(
              label: widget.market.countryName,
              child: Text(
                widget.market.countryName,
                key: const Key('location-market-context'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AsmSpacing.space20),
            Form(
              key: _formKey,
              child: TextFormField(
                key: const Key('location-description'),
                controller: _controller,
                autofocus: true,
                maxLength: 240,
                inputFormatters: [LengthLimitingTextInputFormatter(240)],
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _handleTextChanged,
                onFieldSubmitted: (_) => _useDescription(),
                decoration: InputDecoration(
                  labelText: widget.kind.fieldLabel,
                  hintText: 'e.g. Kotoka Airport, Kempinski Hotel',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter your location.'
                    : null,
              ),
            ),
            if (_searchUnavailable)
              const _SearchNotice(
                key: Key('place-search-unavailable'),
                text:
                    "Place search isn't available right now. You can type "
                    'your pickup and move the pin on the map.',
              ),
            if (_detailsFailed)
              const _SearchNotice(
                key: Key('place-details-failed'),
                text:
                    "Couldn't load that place. Try again, or move the pin "
                    'on the map.',
              ),
            for (final (index, suggestion) in _suggestions.indexed)
              ListTile(
                key: ValueKey('place-suggestion-$index'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(
                  suggestion.mainText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: suggestion.secondaryText.isEmpty
                    ? null
                    : Text(
                        suggestion.secondaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: _resolvingPlaceId == suggestion.placeId
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: () => _pickSuggestion(suggestion),
              ),
            const SizedBox(height: AsmSpacing.space16),
            FilledButton.icon(
              key: const Key('use-location-description'),
              onPressed: _useDescription,
              icon: const Icon(Icons.check),
              label: const Text('Confirm location'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            if (widget.recentDescriptions.isNotEmpty) ...[
              const SizedBox(height: AsmSpacing.space24),
              Text(
                'Recent places',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AsmSpacing.space8),
              for (final (index, description)
                  in widget.recentDescriptions.indexed)
                Semantics(
                  button: true,
                  label: 'Use recent location: $description',
                  child: ListTile(
                    key: ValueKey('recent-location-$index'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history_outlined),
                    title: Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.north_west_outlined),
                    onTap: () => Navigator.of(context).pop(description),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchNotice extends StatelessWidget {
  const _SearchNotice({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AsmColors.brandDeepGreen),
          const SizedBox(width: AsmSpacing.space8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
