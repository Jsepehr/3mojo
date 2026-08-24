import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/start_session_usecase.dart';
import '/features/session/presentation/providers/pro_session.dart';
import '/l10n/generated/app_localizations.dart';

/// Wizard aperto da "Start": prima il selfie (scatta e confermi — un
/// controllo ML Kit verifica al volo che ci sia un volto, altrimenti blocca
/// il passo), poi genere/preferenza. Alla fine avvia la sessione e torna
/// alla home.
class UiStartSession extends StatefulWidget {
  const UiStartSession({super.key});

  @override
  State<UiStartSession> createState() => _UiStartSessionState();
}

class _UiStartSessionState extends State<UiStartSession> {
  int _step = 0;
  String? _selfiePath;
  Uint8List? _selfieBytes;
  Gender? _gender;
  GenderPreference? _genderPreference;
  bool _isCheckingFace = false;

  Future<void> _takeSelfie() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked == null) return;

    final unmirrored = _unmirror(await picked.readAsBytes());
    setState(() {
      _selfiePath = picked.path;
      _selfieBytes = unmirrored;
    });
  }

  /// La fotocamera frontale, su molti dispositivi Android, salva lo scatto
  /// come immagine speculare (mirror-image) invece che come si vede nella
  /// realtà — lo corregge ribaltando l'immagine orizzontalmente una volta.
  /// Tutto in memoria (mai un file temporaneo): funziona identico su ogni
  /// piattaforma, web incluso.
  Uint8List _unmirror(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    return Uint8List.fromList(img.encodeJpg(img.flipHorizontal(decoded)));
  }

  Future<void> _confirmSelfie() async {
    final selfiePath = _selfiePath;
    if (selfiePath == null) return;

    setState(() => _isCheckingFace = true);
    final hasFace = await context.read<ProSession>().checkSelfieHasFace(
      selfiePath,
    );
    if (!mounted) return;

    setState(() {
      _isCheckingFace = false;
      if (hasFace) _step = 1;
    });
  }

  void _submit() {
    final selfiePath = _selfiePath;
    final selfieBytes = _selfieBytes;
    final gender = _gender;
    final genderPreference = _genderPreference;
    if (selfiePath == null ||
        selfieBytes == null ||
        gender == null ||
        genderPreference == null) {
      return;
    }

    context.read<ProSession>().start(
      StartSessionParams(
        selfiePath: selfiePath,
        selfieBytes: selfieBytes,
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
            ? _buildSelfieStep(l10n, errorMessage)
            : _buildGenderStep(l10n, errorMessage),
      ),
    );
  }

  Widget _buildSelfieStep(AppLocalizations l10n, String? errorMessage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: GestureDetector(
            onTap: _takeSelfie,
            child: CircleAvatar(
              radius: 96,
              backgroundImage: _selfieBytes == null
                  ? null
                  : MemoryImage(_selfieBytes!),
              child: _selfieBytes == null
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
          onPressed: _selfiePath == null || _isCheckingFace
              ? null
              : _confirmSelfie,
          child: _isCheckingFace
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.profileLikeSelfieButton),
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
