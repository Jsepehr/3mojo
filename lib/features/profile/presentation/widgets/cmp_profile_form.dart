import 'package:flutter/material.dart';

import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/profile.dart';

class CmpProfileForm extends StatefulWidget {
  const CmpProfileForm({
    super.key,
    required this.profile,
    required this.onSave,
    this.errorMessage,
  });

  final Profile profile;
  final ValueChanged<Profile> onSave;
  final String? errorMessage;

  @override
  State<CmpProfileForm> createState() => _CmpProfileFormState();
}

class _CmpProfileFormState extends State<CmpProfileForm> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.profile.name,
  );
  late final TextEditingController _ageController = TextEditingController(
    text: widget.profile.age.toString(),
  );
  late final TextEditingController _bioController = TextEditingController(
    text: widget.profile.bio,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSave(
      widget.profile.copyWith(
        name: _nameController.text,
        age: int.tryParse(_ageController.text) ?? widget.profile.age,
        bio: _bioController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: l10n.profileNameLabel),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.profileAgeLabel),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bioController,
            maxLines: 3,
            decoration: InputDecoration(labelText: l10n.profileBioLabel),
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            child: Text(l10n.profileSaveButton),
          ),
        ],
      ),
    );
  }
}
