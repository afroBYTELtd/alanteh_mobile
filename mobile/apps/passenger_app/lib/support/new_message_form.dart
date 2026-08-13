import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../network/ghana_network_resilience.dart';
import '../ride_requests/ride_request_history.dart';

const passengerSupportMessageEndpoint = '/api/passenger/support-message/';
const passengerSupportCategoriesEndpoint = '/api/content/support-categories/';

const _fallbackCategories = <String>[
  'Lost item',
  'General enquiry',
  'Trip issue',
  'Other',
];

final RegExp _supportMessageReferencePattern = RegExp(r'^MSG-[A-Z0-9]+$');

abstract interface class PassengerSupportCategoryFetcher {
  Future<List<String>> fetch();
}

final class ApiPassengerSupportCategoryFetcher
    implements PassengerSupportCategoryFetcher {
  const ApiPassengerSupportCategoryFetcher({
    required this.client,
    required this.connectionConfigured,
  });

  factory ApiPassengerSupportCategoryFetcher.withDefaultClient({
    String? baseUrl,
  }) {
    final connectionConfigured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = connectionConfigured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiPassengerSupportCategoryFetcher(
      client: GhanaResilientApiClient(baseUrl: resolvedBaseUrl),
      connectionConfigured: connectionConfigured,
    );
  }

  final AsmApiClient client;
  final bool connectionConfigured;

  @override
  Future<List<String>> fetch() async {
    if (!connectionConfigured) {
      throw const FormatException('Support category API is not configured.');
    }

    final response = await client.get<Map<String, Object?>>(
      passengerSupportCategoriesEndpoint,
      decoder: _decodeObjectMap,
    );

    if (!response.isSuccess ||
        response.statusCode != 200 ||
        response.data == null) {
      throw const FormatException('Unable to load support categories.');
    }

    final rawCategories = response.data!['categories'];
    if (rawCategories is! List || rawCategories.isEmpty) {
      throw const FormatException('Support categories are unusable.');
    }

    final categories = <String>[];
    final seen = <String>{};

    for (final value in rawCategories) {
      if (value is! String) {
        throw const FormatException('Support categories are unusable.');
      }

      final category = value.trim();
      if (category.isEmpty || !seen.add(category)) {
        throw const FormatException('Support categories are unusable.');
      }

      categories.add(category);
    }

    return List<String>.unmodifiable(categories);
  }
}

List<String>? _cachedSupportCategories;
Future<List<String>>? _supportCategoriesLoadInFlight;
PassengerSupportCategoryFetcher? _supportCategoryFetcherForTesting;

Future<List<String>> _loadPassengerSupportCategories() async {
  final cached = _cachedSupportCategories;
  if (cached != null) {
    return cached;
  }

  final inFlight = _supportCategoriesLoadInFlight;
  if (inFlight != null) {
    return inFlight;
  }

  final fetcher =
      _supportCategoryFetcherForTesting ??
      ApiPassengerSupportCategoryFetcher.withDefaultClient(
        baseUrl: AsmApiClient.defaultBaseUrl,
      );

  final load = _fetchAndCachePassengerSupportCategories(fetcher);
  _supportCategoriesLoadInFlight = load;

  try {
    return await load;
  } finally {
    if (identical(_supportCategoriesLoadInFlight, load)) {
      _supportCategoriesLoadInFlight = null;
    }
  }
}

Future<List<String>> _fetchAndCachePassengerSupportCategories(
  PassengerSupportCategoryFetcher fetcher,
) async {
  try {
    final categories = await fetcher.fetch();
    if (categories.isEmpty) {
      return _fallbackCategories;
    }

    final cachedCategories = List<String>.unmodifiable(categories);
    _cachedSupportCategories = cachedCategories;
    return cachedCategories;
  } on Object {
    return _fallbackCategories;
  }
}

void setPassengerSupportCategoryFetcherForTesting(
  PassengerSupportCategoryFetcher? fetcher,
) {
  _supportCategoryFetcherForTesting = fetcher;
  _cachedSupportCategories = null;
  _supportCategoriesLoadInFlight = null;
}

void resetPassengerSupportCategorySessionForTesting() {
  _supportCategoryFetcherForTesting = null;
  _cachedSupportCategories = null;
  _supportCategoriesLoadInFlight = null;
}

final class PassengerSupportMessageResult {
  const PassengerSupportMessageResult({required this.reference});

  final String reference;
}

abstract interface class PassengerSupportMessageSubmitter {
  Future<PassengerSupportMessageResult> submit({
    required String category,
    required String? tripReference,
    required String name,
    required String message,
  });
}

final class ApiPassengerSupportMessageSubmitter
    implements PassengerSupportMessageSubmitter {
  const ApiPassengerSupportMessageSubmitter(
    this.client, {
    required this.tokenStore,
    this.authService,
    this.connectionConfigured = true,
  });

  factory ApiPassengerSupportMessageSubmitter.withDefaultClient({
    AuthTokenStore? tokenStore,
    String? baseUrl,
  }) {
    final store = tokenStore ?? SecureAuthTokenStore();
    final connectionConfigured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = connectionConfigured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiPassengerSupportMessageSubmitter(
      GhanaResilientApiClient(
        baseUrl: resolvedBaseUrl,
        tokenProvider: _SupportMessageTokenProvider(store),
      ),
      tokenStore: store,
      authService: connectionConfigured
          ? AuthService.withApiClient(
              client: GhanaResilientApiClient(baseUrl: resolvedBaseUrl),
              tokenStore: store,
            )
          : null,
      connectionConfigured: connectionConfigured,
    );
  }

  final AsmApiClient client;
  final AuthTokenStore tokenStore;
  final AuthService? authService;
  final bool connectionConfigured;

  @override
  Future<PassengerSupportMessageResult> submit({
    required String category,
    required String? tripReference,
    required String name,
    required String message,
  }) async {
    final accessToken = (await tokenStore.readAccessToken())?.trim();
    if (accessToken == null || accessToken.isEmpty) {
      throw const PassengerSupportMessageException.signInRequired();
    }

    if (!connectionConfigured) {
      throw const PassengerSupportMessageException.connectionNotConfigured();
    }

    final response = await _post(
      category: category,
      tripReference: tripReference,
      name: name,
      message: message,
    );

    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        throw const PassengerSupportMessageException.signInRequired();
      }

      final retryResponse = await _post(
        category: category,
        tripReference: tripReference,
        name: name,
        message: message,
      );

      if (retryResponse.statusCode == 401) {
        await tokenStore.clearTokens();
      }

      return _resultFromResponse(retryResponse);
    }

    return _resultFromResponse(response);
  }

  Future<ApiResponse<Map<String, Object?>>> _post({
    required String category,
    required String? tripReference,
    required String name,
    required String message,
  }) {
    return client.post<Map<String, Object?>>(
      passengerSupportMessageEndpoint,
      data: <String, Object?>{
        'category': category,
        'trip_reference': tripReference,
        'name': name,
        'message': message,
        'attachment_url': null,
      },
      decoder: _decodeObjectMap,
    );
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = (await tokenStore.readRefreshToken())?.trim();
    final service = authService;

    if (refreshToken == null || refreshToken.isEmpty || service == null) {
      await tokenStore.clearTokens();
      return false;
    }

    try {
      final state = await service.refresh();
      if (state.isAuthenticated) {
        return true;
      }
    } on Object {
      // The user-facing state remains intentionally generic.
    }

    await tokenStore.clearTokens();
    return false;
  }

  PassengerSupportMessageResult _resultFromResponse(
    ApiResponse<Map<String, Object?>> response,
  ) {
    if (response.isSuccess &&
        response.statusCode == 201 &&
        response.data != null) {
      final reference = _supportReferenceFromResponse(response.data!);
      if (reference != null &&
          _supportMessageReferencePattern.hasMatch(reference)) {
        return PassengerSupportMessageResult(reference: reference);
      }
    }

    throw PassengerSupportMessageException.fromResponse(response);
  }
}

final class PassengerSupportMessageException implements Exception {
  const PassengerSupportMessageException(this.message);

  const PassengerSupportMessageException.signInRequired()
    : message = 'Please sign in again to send a message.';

  const PassengerSupportMessageException.connectionNotConfigured()
    : message = AsmApiClient.connectionNotConfiguredMessage;

  final String message;

  factory PassengerSupportMessageException.fromResponse(
    ApiResponse<Map<String, Object?>> response,
  ) {
    final error = response.error;

    if (error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout) {
      return const PassengerSupportMessageException(
        'Cannot reach the server. Check your connection and try again.',
      );
    }

    if (response.statusCode == 404 ||
        response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504 ||
        error?.type == AsmApiExceptionType.server) {
      return const PassengerSupportMessageException(
        'Support messaging is temporarily unavailable. Please try again later.',
      );
    }

    if (response.statusCode == 401) {
      return const PassengerSupportMessageException.signInRequired();
    }

    return const PassengerSupportMessageException(
      'Unable to send your message. Please try again.',
    );
  }

  @override
  String toString() => message;
}

final class _SupportMessageTokenProvider implements TokenProvider {
  const _SupportMessageTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}

abstract interface class PassengerImagePicker {
  Future<String?> pickImagePath();
}

final class PlatformPassengerImagePicker implements PassengerImagePicker {
  PlatformPassengerImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pickImagePath() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    final path = image?.path.trim();
    return path == null || path.isEmpty ? null : path;
  }
}

class NewMessageForm extends StatefulWidget {
  const NewMessageForm({
    this.initialCategory,
    this.initialPassengerName,
    required this.tripHistoryRepository,
    required this.submitter,
    this.imagePicker,
    super.key,
  });

  final String? initialCategory;
  final String? initialPassengerName;
  final PassengerRideRequestHistoryRepository tripHistoryRepository;
  final PassengerSupportMessageSubmitter submitter;
  final PassengerImagePicker? imagePicker;

  @override
  State<NewMessageForm> createState() => _NewMessageFormState();
}

class _NewMessageFormState extends State<NewMessageForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _messageController = TextEditingController();

  late final PassengerImagePicker _imagePicker;
  late String? _selectedCategory;

  List<String> _categoryOptions = const <String>[];
  String? _selectedTripReference;
  PassengerRideRequestRecord? _selectedTrip;
  String? _attachmentPath;
  String? _submissionError;
  String? _successReference;
  bool _loadingCategories = true;
  bool _submitting = false;

  bool get _categoryLocked => widget.initialCategory != null;

  @override
  void initState() {
    super.initState();
    _imagePicker = widget.imagePicker ?? PlatformPassengerImagePicker();
    _selectedCategory = widget.initialCategory;

    final initialCategory = _selectedCategory?.trim();
    if (initialCategory != null && initialCategory.isNotEmpty) {
      _categoryOptions = <String>[initialCategory];
    }

    final initialName = widget.initialPassengerName?.trim();
    if (initialName != null && initialName.isNotEmpty) {
      _nameController.text = initialName;
    }

    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await _loadPassengerSupportCategories();
    if (!mounted) {
      return;
    }

    final options = List<String>.of(categories);
    final selectedCategory = _selectedCategory?.trim();

    if (selectedCategory != null &&
        selectedCategory.isNotEmpty &&
        !options.contains(selectedCategory)) {
      options.insert(0, selectedCategory);
    }

    setState(() {
      _categoryOptions = List<String>.unmodifiable(options);
      _loadingCategories = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _openTripPicker() async {
    final selected = await showModalBottomSheet<PassengerRideRequestRecord>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PassengerSupportTripPicker(
        repository: widget.tripHistoryRepository,
        selectedTripReference: _selectedTripReference,
      ),
    );

    if (!mounted || selected == null) {
      return;
    }

    final reference = selected.normalizedTripReference;
    if (reference == null) {
      return;
    }

    setState(() {
      _selectedTripReference = reference;
      _selectedTrip = selected;
    });
  }

  Future<void> _chooseAttachment() async {
    try {
      final path = await _imagePicker.pickImagePath();
      if (!mounted || path == null) {
        return;
      }

      setState(() => _attachmentPath = path);
    } on PlatformException {
      if (mounted) {
        await _showPhotoAccessDialog();
      }
    } on Object {
      if (mounted) {
        await _showPhotoAccessDialog();
      }
    }
  }

  Future<void> _showPhotoAccessDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('new-message-photo-access-dialog'),
        title: const Text('Photo access unavailable'),
        content: const Text(
          'ALANTEH could not access your photos. Please allow photo access '
          'in your device settings and try again.',
        ),
        actions: [
          TextButton(
            key: const Key('new-message-photo-access-ok'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (_submitting || form == null || !form.validate()) {
      return;
    }

    final category = _selectedCategory?.trim();
    if (category == null || category.isEmpty) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _submitting = true;
      _submissionError = null;
    });

    try {
      final result = await widget.submitter.submit(
        category: category,
        tripReference: _selectedTripReference,
        name: _nameController.text.trim(),
        message: _messageController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
        _successReference = result.reference;
      });
    } on PassengerSupportMessageException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
        _submissionError = error.message;
      });
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
        _submissionError = 'Unable to send your message. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final successReference = _successReference;
    if (successReference != null) {
      return _MessageSentScreen(reference: successReference);
    }

    return Scaffold(
      key: const Key('new-message-form'),
      appBar: AppBar(title: const Text('New message')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AsmSpacing.space16,
            AsmSpacing.space16,
            AsmSpacing.space16,
            AsmSpacing.space12,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Need help? Send us a message and we will get back to you.',
                  key: Key('new-message-intro'),
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.35),
                ),
                const SizedBox(height: AsmSpacing.space16),
                TextFormField(
                  key: const Key('new-message-name'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (normalized.isEmpty) {
                      return 'Name is required.';
                    }
                    if (normalized.length < 2) {
                      return 'Name must be at least 2 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AsmSpacing.space12),
                DropdownButtonFormField<String>(
                  key: const Key('new-message-category'),
                  initialValue: _selectedCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categoryOptions
                      .map(
                        (category) => DropdownMenuItem<String>(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _categoryLocked || _loadingCategories
                      ? null
                      : (value) => setState(() => _selectedCategory = value),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (normalized.isEmpty) {
                      return 'Category is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AsmSpacing.space12),
                InkWell(
                  key: const Key('new-message-trip'),
                  onTap: _openTripPicker,
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Choose trip (optional)',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    isEmpty: _selectedTrip == null,
                    child: _selectedTrip == null
                        ? const Text('Select a trip (optional)')
                        : Text(
                            '${_selectedTrip!.pickupLocation} → '
                            '${_selectedTrip!.destination}\n'
                            '${_formatSupportTripDate(_selectedTrip!.createdAt)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
                const SizedBox(height: AsmSpacing.space12),
                Expanded(
                  child: TextFormField(
                    key: const Key('new-message-message'),
                    controller: _messageController,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final normalized = value?.trim() ?? '';
                      if (normalized.isEmpty) {
                        return 'Message is required.';
                      }
                      if (normalized.length < 10) {
                        return 'Message must be at least 10 characters.';
                      }
                      return null;
                    },
                  ),
                ),
                if (_attachmentPath case final path?) ...[
                  const SizedBox(height: AsmSpacing.space8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AsmRadii.radius8),
                      child: Image.file(
                        File(path),
                        key: const Key('new-message-attachment-thumbnail'),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          key: const Key(
                            'new-message-attachment-thumbnail-fallback',
                          ),
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: AsmColors.passengerLine),
                            borderRadius: BorderRadius.circular(
                              AsmRadii.radius8,
                            ),
                          ),
                          child: const Icon(Icons.image_outlined),
                        ),
                      ),
                    ),
                  ),
                ],
                if (_submissionError case final error?) ...[
                  const SizedBox(height: AsmSpacing.space8),
                  Container(
                    key: const Key('new-message-failure-state'),
                    padding: const EdgeInsets.all(AsmSpacing.space12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AsmColors.passengerLine),
                      borderRadius: BorderRadius.circular(AsmRadii.radius8),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(error)),
                        const SizedBox(width: AsmSpacing.space8),
                        TextButton(
                          key: const Key('new-message-retry'),
                          onPressed: _submitting ? null : _submit,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AsmSpacing.space8),
                Row(
                  key: const Key('new-message-bottom-actions'),
                  children: [
                    IconButton(
                      key: const Key('new-message-attachment'),
                      tooltip: 'Add image',
                      onPressed: _submitting ? null : _chooseAttachment,
                      icon: const Icon(Icons.attach_file),
                    ),
                    const SizedBox(width: AsmSpacing.space12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('new-message-send'),
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PassengerSupportTripPicker extends StatefulWidget {
  const _PassengerSupportTripPicker({
    required this.repository,
    required this.selectedTripReference,
  });

  final PassengerRideRequestHistoryRepository repository;
  final String? selectedTripReference;

  @override
  State<_PassengerSupportTripPicker> createState() =>
      _PassengerSupportTripPickerState();
}

class _PassengerSupportTripPickerState
    extends State<_PassengerSupportTripPicker> {
  late Future<List<PassengerRideRequestRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PassengerRideRequestRecord>> _load() async {
    final records = await widget.repository.fetchRequests();
    final seen = <String>{};
    final options = <PassengerRideRequestRecord>[];

    for (final record in records) {
      final reference = record.normalizedTripReference;
      if (reference == null || !seen.add(reference)) {
        continue;
      }
      options.add(record);
    }

    return List<PassengerRideRequestRecord>.unmodifiable(options);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        key: const Key('new-message-trip-picker'),
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space16,
          AsmSpacing.space20,
          AsmSpacing.space16,
          AsmSpacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose trip',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space4),
            const Text('Optional — select a trip related to this message.'),
            const SizedBox(height: AsmSpacing.space16),
            Flexible(
              child: FutureBuilder<List<PassengerRideRequestRecord>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      key: Key('new-message-trip-loading'),
                      child: Padding(
                        padding: EdgeInsets.all(AsmSpacing.space24),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Column(
                      key: const Key('new-message-trip-error'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Unable to load trip history. Please try again.',
                        ),
                        const SizedBox(height: AsmSpacing.space12),
                        OutlinedButton(
                          key: const Key('new-message-trip-retry'),
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    );
                  }

                  final options =
                      snapshot.data ?? const <PassengerRideRequestRecord>[];
                  if (options.isEmpty) {
                    return const Padding(
                      key: Key('new-message-trip-empty'),
                      padding: EdgeInsets.all(AsmSpacing.space24),
                      child: Text(
                        'No trips are available to attach to this message.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: AsmSpacing.space16),
                    itemBuilder: (context, index) {
                      final record = options[index];
                      final reference = record.normalizedTripReference!;
                      return ListTile(
                        key: ValueKey('new-message-trip-option-$reference'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${record.pickupLocation} → ${record.destination}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _formatSupportTripDate(record.createdAt),
                        ),
                        trailing: reference == widget.selectedTripReference
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.of(context).pop(record),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageSentScreen extends StatelessWidget {
  const _MessageSentScreen({required this.reference});

  final String reference;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('new-message-success'),
      appBar: AppBar(title: const Text('Message sent')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AsmSpacing.space24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_outline, size: 64),
              const SizedBox(height: AsmSpacing.space16),
              const Text(
                'Message sent',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AsmSpacing.space12),
              const Text(
                'Your message has been received.\n'
                'We will get back to you shortly.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AsmSpacing.space12),
              Text(
                'Reference: $reference',
                key: const Key('new-message-success-reference'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AsmSpacing.space24),
              FilledButton(
                key: const Key('new-message-done'),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _supportReferenceFromResponse(Map<String, Object?> data) {
  for (final key in const [
    'ticket_reference',
    'message_reference',
    'reference',
  ]) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

Map<String, Object?> _decodeObjectMap(Object? json) {
  if (json is Map<String, Object?>) {
    return json;
  }

  if (json is Map) {
    return json.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  throw const FormatException('Expected a JSON object.');
}

String _formatSupportTripDate(DateTime? value) {
  if (value == null) {
    return 'Date not available';
  }

  final local = value.toLocal();
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
