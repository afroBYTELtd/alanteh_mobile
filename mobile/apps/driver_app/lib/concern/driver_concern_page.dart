import 'package:asm_app_config/asm_app_config.dart';
import 'package:flutter/material.dart';

import 'driver_concern_draft.dart';
import 'driver_concern_form.dart';
import 'driver_concern_review.dart';

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

  String get _marketLabel =>
      '${widget.market.city}, ${widget.market.countryName}';

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
    });
  }

  void _edit() {
    setState(() => _reviewDraft = null);
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle concern')),
      body: SafeArea(
        child: _reviewDraft == null
            ? DriverConcernForm(
                marketLabel: _marketLabel,
                formKey: _formKey,
                category: _category,
                attentionLevel: _attentionLevel,
                descriptionController: _descriptionController,
                onCategoryChanged: (value) => setState(() => _category = value),
                onAttentionLevelChanged: (value) =>
                    setState(() => _attentionLevel = value),
                onReview: _review,
              )
            : DriverConcernReview(
                marketLabel: _marketLabel,
                draft: _reviewDraft!,
                onEdit: _edit,
                onClose: _close,
              ),
      ),
    );
  }
}
