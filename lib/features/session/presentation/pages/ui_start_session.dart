import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '/core/widgets/cmp_loading_indicator.dart';
import '/core/widgets/cmp_photo.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/start_session_usecase.dart';
import '/features/session/presentation/providers/pro_session.dart';
import '/l10n/generated/app_localizations.dart';

/// Decodifica/ribalta/codifica un JPEG: eseguito su un isolate separato
/// tramite [compute] (per questo è una funzione top-level, non un metodo),
/// così il ribaltamento manuale non blocca il frame in corso.
Uint8List _flipImageBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  return Uint8List.fromList(img.encodeJpg(img.flipHorizontal(decoded)));
}

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
  bool _isFlipping = false;

  Future<void> _takeSelfie() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _selfiePath = picked.path;
      _selfieBytes = bytes;
    });
  }

  /// La fotocamera frontale, su molti dispositivi Android, salva lo scatto
  /// come immagine speculare (mirror-image) invece che come si vede nella
  /// realtà: l'utente decide se serve la correzione col bottone sopra il
  /// selfie, che ribalta l'immagine orizzontalmente. Tutto in memoria (mai
  /// un file temporaneo): funziona identico su ogni piattaforma, web incluso.
  /// Gira su un isolate separato (compute) perché decode/encode JPEG è
  /// abbastanza pesante da bloccare il frame se girasse sulla UI.
  Future<void> _flipSelfie() async {
    final bytes = _selfieBytes;
    if (bytes == null) return;

    setState(() => _isFlipping = true);
    final flipped = await compute(_flipImageBytes, bytes);
    if (!mounted) return;

    setState(() {
      _selfieBytes = flipped;
      _isFlipping = false;
    });
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
      appBar: AppBar(title: Text(l10n.go_online)),
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: _takeSelfie,
                child: CmpPhoto(
                  image: _selfieBytes == null
                      ? null
                      : MemoryImage(_selfieBytes!),
                  size: 220,
                  placeholderIcon: Icons.camera_alt,
                ),
              ),
              if (_isFlipping)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(
                        CmpPhoto.cornerRadius,
                      ),
                    ),
                    child: const Center(
                      child: CmpLoadingIndicator(color: Colors.white),
                    ),
                  ),
                ),
              if (_selfieBytes != null)
                Positioned(
                  top: -8,
                  right: -8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _isFlipping ? null : _flipSelfie,
                      tooltip: l10n.flip_photo,
                      icon: Icon(
                        Icons.flip,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _takeSelfie,
            child: Text(
              _selfiePath == null
                  ? l10n.take_a_selfie
                  : l10n.retake,
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
              ? CmpLoadingIndicator(
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimary,
                )
              : Text(l10n.i_like_it_continue),
        ),
      ],
    );
  }

  Widget _buildGenderStep(AppLocalizations l10n, String? errorMessage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.you_are,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<Gender>(
          segments: [
            ButtonSegment(
              value: Gender.male,
              label: Text(l10n.male),
            ),
            ButtonSegment(
              value: Gender.female,
              label: Text(l10n.female),
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
          l10n.looking_for,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<GenderPreference>(
          segments: [
            ButtonSegment(
              value: GenderPreference.male,
              label: Text(l10n.male),
            ),
            ButtonSegment(
              value: GenderPreference.female,
              label: Text(l10n.female),
            ),
            ButtonSegment(
              value: GenderPreference.everyone,
              label: Text(l10n.everyone),
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
          child: Text(l10n.go_online_2),
        ),
      ],
    );
  }
}
