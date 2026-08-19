import 'dart:async';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import '../network/driver_report_gateway.dart';
import 'driver_concern_draft.dart';
import 'driver_concern_form.dart';

enum _DriverConcernScreen { form, submitted }

class DriverConcernPage extends StatefulWidget {
  const DriverConcernPage({required this.market, this.gateway, super.key});

  final MarketConfig market;
  final DriverReportGateway? gateway;

  @override
  State<DriverConcernPage> createState() => _DriverConcernPageState();
}

class _DriverConcernPageState extends State<DriverConcernPage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  List<String> _categories = const <String>[];
  String? _category;
  DriverConcernAttentionLevel? _attentionLevel;
  String? _categoriesError;
  String? _submissionError;
  String? _reportReference;
  bool _categoriesLoading = true;
  bool _submitting = false;
  _DriverConcernScreen _screen = _DriverConcernScreen.form;

  String get _marketLabel => widget.market.countryName;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCategories());
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories({bool forceRefresh = false}) async {
    if (_submitting) {
      return;
    }

    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });

    final gateway = widget.gateway;
    if (gateway == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _categoriesLoading = false;
        _categoriesError = AsmApiClient.connectionNotConfiguredMessage;
      });
      return;
    }

    try {
      final categories = await gateway.fetchCategories(
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _categories = categories;
        if (_category != null && !categories.contains(_category)) {
          _category = null;
        }
        _categoriesLoading = false;
        _categoriesError = null;
      });
    } on DriverReportException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _categoriesLoading = false;
        _categoriesError = error.message;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _categoriesLoading = false;
        _categoriesError =
            'Report categories are temporarily unavailable. '
            'Check your connection and retry.';
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final gateway = widget.gateway;
    if (gateway == null) {
      setState(() {
        _submissionError = AsmApiClient.connectionNotConfiguredMessage;
      });
      return;
    }

    final category = _category;
    final attentionLevel = _attentionLevel;
    if (category == null || attentionLevel == null) {
      return;
    }

    final draft = DriverConcernDraft(
      marketCode: widget.market.marketCode,
      category: category,
      attentionLevel: attentionLevel,
      description: _descriptionController.text,
    );

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitting = true;
      _submissionError = null;
    });

    try {
      final receipt = await gateway.submit(
        category: draft.category,
        description: draft.description,
        urgency: draft.urgency,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
        _submissionError = null;
        _reportReference = receipt.reportReference;
        _screen = _DriverConcernScreen.submitted;
      });
    } on DriverReportException catch (error) {
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
        _submissionError =
            'Your report could not be sent. '
            'Check your connection and retry.';
      });
    }
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('driver-concern-page'),
      appBar: AppBar(
        title: Text(
          _screen == _DriverConcernScreen.form
              ? 'Report an issue'
              : 'Report sent',
        ),
      ),
      body: SafeArea(
        child: _screen == _DriverConcernScreen.form
            ? DriverConcernForm(
                marketLabel: _marketLabel,
                formKey: _formKey,
                categories: _categories,
                category: _category,
                attentionLevel: _attentionLevel,
                descriptionController: _descriptionController,
                categoriesLoading: _categoriesLoading,
                categoriesError: _categoriesError,
                submitting: _submitting,
                submissionError: _submissionError,
                onCategoryChanged: (value) {
                  setState(() {
                    _category = value;
                    _submissionError = null;
                  });
                },
                onAttentionLevelChanged: (value) {
                  setState(() {
                    _attentionLevel = value;
                    _submissionError = null;
                  });
                },
                onRetryCategories: () {
                  unawaited(_loadCategories(forceRefresh: true));
                },
                onSend: () {
                  unawaited(_submit());
                },
                onRetrySubmission: () {
                  unawaited(_submit());
                },
              )
            : _DriverConcernSubmitted(
                reportReference: _reportReference!,
                onBackToHome: _close,
              ),
      ),
    );
  }
}

class _DriverConcernSubmitted extends StatelessWidget {
  const _DriverConcernSubmitted({
    required this.reportReference,
    required this.onBackToHome,
  });

  final String reportReference;
  final VoidCallback onBackToHome;

  @override
  Widget build(BuildContext context) {
    return AsmScreenSurface(
      key: const Key('concern-submitted'),
      scrollable: true,
      expandToViewport: true,
      padding: const EdgeInsets.all(AsmSpacing.space24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 42,
              backgroundColor: AsmColors.driverCardElevated,
              foregroundColor: AsmColors.driverMintAction,
              child: Icon(Icons.check_circle_outline, size: 45),
            ),
            const SizedBox(height: AsmSpacing.space20),
            const Text(
              'Report sent',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space12),
            const Text(
              'Your report has been received.',
              key: Key('concern-success-message'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AsmColors.driverTextSecondary,
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AsmSpacing.space20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AsmSpacing.space16),
              decoration: BoxDecoration(
                color: AsmColors.driverCardElevated,
                borderRadius: BorderRadius.circular(AsmRadii.radius16),
                border: Border.all(color: AsmColors.driverLine),
              ),
              child: Column(
                children: [
                  const Text(
                    'Report reference',
                    style: TextStyle(
                      color: AsmColors.driverTextSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space4),
                  Text(
                    reportReference,
                    key: const Key('concern-report-reference'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AsmSpacing.space32),
            OutlinedButton.icon(
              key: const Key('concern-back-home'),
              onPressed: onBackToHome,
              icon: const Icon(Icons.arrow_back_outlined),
              label: const Text('Back to home'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
