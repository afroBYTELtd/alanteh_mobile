import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    super.key,
  });

  final LocationSearchKind kind;
  final MarketConfig market;
  final String? initialDescription;
  final List<String> recentDescriptions;

  @override
  State<LocationSearchPage> createState() => _LocationSearchPageState();
}

class _LocationSearchPageState extends State<LocationSearchPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDescription ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
