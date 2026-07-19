import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_concern_draft.dart';
import 'driver_concern_form.dart';
import 'driver_concern_review.dart';

enum _DriverConcernScreen { form, review, submitted }

class DriverConcernPage extends StatefulWidget {
  const DriverConcernPage({required this.market, super.key});

  final MarketConfig market;

  @override
  State<DriverConcernPage> createState() => _DriverConcernPageState();
}

class _DriverConcernPageState extends State<DriverConcernPage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  DriverConcernCategory? _category;
  DriverConcernAttentionLevel? _attentionLevel;
  DriverConcernDraft? _reviewDraft;
  _DriverConcernScreen _screen = _DriverConcernScreen.form;

  String get _marketLabel => widget.market.countryName;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _review() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _reviewDraft = DriverConcernDraft(
        marketCode: widget.market.marketCode,
        category: _category!,
        attentionLevel: _attentionLevel!,
        description: _descriptionController.text,
      );
      _screen = _DriverConcernScreen.review;
    });
  }

  void _edit() {
    setState(() => _screen = _DriverConcernScreen.form);
  }

  void _confirm() {
    setState(() => _screen = _DriverConcernScreen.submitted);
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('driver-concern-page'),
      appBar: AppBar(
        title: Text(switch (_screen) {
          _DriverConcernScreen.form => 'Report an issue',
          _DriverConcernScreen.review => 'Review report',
          _DriverConcernScreen.submitted => 'Report sent',
        }),
      ),
      body: SafeArea(
        child: switch (_screen) {
          _DriverConcernScreen.form => DriverConcernForm(
            marketLabel: _marketLabel,
            formKey: _formKey,
            category: _category,
            attentionLevel: _attentionLevel,
            descriptionController: _descriptionController,
            onCategoryChanged: (value) {
              setState(() => _category = value);
            },
            onAttentionLevelChanged: (value) {
              setState(() => _attentionLevel = value);
            },
            onReview: _review,
          ),
          _DriverConcernScreen.review => DriverConcernReview(
            marketLabel: _marketLabel,
            draft: _reviewDraft!,
            onConfirm: _confirm,
            onEdit: _edit,
            onClose: _close,
          ),
          _DriverConcernScreen.submitted => _DriverConcernSubmitted(
            onBackToHome: _close,
          ),
        },
      ),
    );
  }
}

class _DriverConcernSubmitted extends StatelessWidget {
  const _DriverConcernSubmitted({required this.onBackToHome});

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
              "ALANTEH's operations team has received your report and "
              'will follow up if needed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AsmColors.driverTextSecondary,
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w600,
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
