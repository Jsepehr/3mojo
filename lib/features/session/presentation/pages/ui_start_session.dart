import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/online_session.dart';
import '../../domain/usecases/start_session_usecase.dart';
import '../providers/pro_session.dart';

class UiStartSession extends StatefulWidget {
  const UiStartSession({super.key});

  @override
  State<UiStartSession> createState() => _UiStartSessionState();
}

class _UiStartSessionState extends State<UiStartSession> {
  int _step = 0;
  String? _selfiePath;
  Gender? _gender;
  GenderPreference? _genderPreference;

  Future<void> _takeSelfie() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked != null) {
      setState(() => _selfiePath = picked.path);
    }
  }

  void _confirmSelfie() => setState(() => _step = 1);

  void _submit() {
    final selfiePath = _selfiePath;
    final gender = _gender;
    final genderPreference = _genderPreference;
    if (selfiePath == null || gender == null || genderPreference == null) {
      return;
    }

    context.read<ProSession>().start(
      StartSessionParams(
        selfiePath: selfiePath,
        gender: gender,
        genderPreference: genderPreference,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = context.watch<ProSession>().errorMessage;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.startSessionPageTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _step == 0
            ? _buildSelfieStep(l10n)
            : _buildGenderStep(l10n, errorMessage),
      ),
    );
  }

  Widget _buildSelfieStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: GestureDetector(
            onTap: _takeSelfie,
            child: CircleAvatar(
              radius: 96,
              backgroundImage: _selfiePath == null
                  ? null
                  : FileImage(File(_selfiePath!)),
              child: _selfiePath == null
                  ? const Icon(Icons.camera_alt, size: 40)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _takeSelfie,
            child: Text(
              _selfiePath == null
                  ? l10n.profileTakeSelfieButton
                  : l10n.profileRetakeSelfieButton,
            ),
          ),
        ),
        const Spacer(),
        FilledButton(
          onPressed: _selfiePath == null ? null : _confirmSelfie,
          child: Text(l10n.profileLikeSelfieButton),
        ),
      ],
    );
  }

  Widget _buildGenderStep(AppLocalizations l10n, String? errorMessage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.profileGenderQuestion,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<Gender>(
          segments: [
            ButtonSegment(
              value: Gender.male,
              label: Text(l10n.profileGenderMale),
            ),
            ButtonSegment(
              value: Gender.female,
              label: Text(l10n.profileGenderFemale),
            ),
          ],
          selected: _gender == null ? {} : {_gender!},
          emptySelectionAllowed: true,
          onSelectionChanged: (selection) => setState(
            () => _gender = selection.isEmpty ? null : selection.first,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.profileGenderPreferenceQuestion,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<GenderPreference>(
          segments: [
            ButtonSegment(
              value: GenderPreference.male,
              label: Text(l10n.profileGenderMale),
            ),
            ButtonSegment(
              value: GenderPreference.female,
              label: Text(l10n.profileGenderFemale),
            ),
            ButtonSegment(
              value: GenderPreference.everyone,
              label: Text(l10n.profileGenderPreferenceEveryone),
            ),
          ],
          selected: _genderPreference == null ? {} : {_genderPreference!},
          emptySelectionAllowed: true,
          onSelectionChanged: (selection) => setState(
            () =>
                _genderPreference = selection.isEmpty ? null : selection.first,
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const Spacer(),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.startSessionSubmitButton),
        ),
      ],
    );
  }
}
