import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_trip_safety.dart';

class DriverSafetySettingsScreen extends StatefulWidget {
  const DriverSafetySettingsScreen({
    required this.repository,
    super.key,
  });

  final DriverTrustedContactRepository repository;

  @override
  State<DriverSafetySettingsScreen> createState() =>
      _DriverSafetySettingsScreenState();
}

class _DriverSafetySettingsScreenState
    extends State<DriverSafetySettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  DriverTrustedContact _contact = const DriverTrustedContact.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final contact = await widget.repository.fetch();
      if (!mounted) {
        return;
      }

      _applyContact(contact);
      setState(() {
        _contact = contact;
        _loading = false;
      });
    } on DriverTrustedContactException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() => _loading = false);
      _showMessage(error.message);
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() => _loading = false);
      _showMessage('Unable to load your trusted contact. Please try again.');
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);

    try {
      final saved = await widget.repository.save(
        name: _nameController.text,
        phone: _phoneController.text,
      );

      if (!mounted) {
        return;
      }

      _applyContact(saved);
      setState(() {
        _contact = saved;
        _saving = false;
      });
      _showMessage('Trusted contact saved.');
    } on DriverTrustedContactException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() => _saving = false);
      _showMessage(error.message);
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() => _saving = false);
      _showMessage('Unable to save your trusted contact. Please try again.');
    }
  }

  void _applyContact(DriverTrustedContact contact) {
    _nameController.text = contact.name;
    _phoneController.text = contact.phone;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _requiredValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: const Key('driver-safety-settings-screen'),
      appBar: AppBar(title: const Text('Safety & emergency')),
      body: AsmScreenSurface(
        scrollable: true,
        padding: const EdgeInsets.fromLTRB(
          AsmSpacing.space16,
          AsmSpacing.space16,
          AsmSpacing.space16,
          AsmSpacing.space32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Trusted contact',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              'Choose someone you trust who can receive your trip details by message.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AsmSpacing.space16),
            if (_contact.isConfigured)
              Card(
                key: const Key('driver-trusted-contact-saved-card'),
                elevation: 0,
                color: AsmColors.driverCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AsmRadii.radius20),
                  side: const BorderSide(color: AsmColors.driverLine),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AsmColors.driverMintAction,
                    foregroundColor: AsmColors.driverScaffold,
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(
                    _contact.name,
                    key: const Key('driver-trusted-contact-saved-name'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _contact.phone,
                    key: const Key('driver-trusted-contact-saved-phone'),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                ),
              ),
            if (_contact.isConfigured)
              const SizedBox(height: AsmSpacing.space16),
            Card(
              elevation: 0,
              color: AsmColors.driverCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AsmRadii.radius20),
                side: const BorderSide(color: AsmColors.driverLine),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AsmSpacing.space16),
                child: _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AsmSpacing.space16),
                          child: CircularProgressIndicator(
                            color: AsmColors.driverMintAction,
                          ),
                        ),
                      )
                    : Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              key: const Key('driver-trusted-contact-name'),
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                hintText: 'Trusted contact name',
                              ),
                              validator: _requiredValue,
                            ),
                            const SizedBox(height: AsmSpacing.space16),
                            TextFormField(
                              key: const Key('driver-trusted-contact-phone'),
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Phone number',
                                hintText: 'Phone number',
                              ),
                              validator: _requiredValue,
                              onFieldSubmitted: (_) => _save(),
                            ),
                            const SizedBox(height: AsmSpacing.space20),
                            FilledButton.icon(
                              key: const Key('driver-trusted-contact-save'),
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.shield_outlined),
                              label: Text(
                                _saving ? 'Saving…' : 'Save contact',
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
