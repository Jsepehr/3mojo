import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Un record di moderazione: ciò che resta, per una revisione umana, delle
/// segnalazioni ricevute da **una** sessione. È il **primo e unico dato
/// che il server conserva** oltre la vita delle sessioni, quindi contiene
/// solo lo stretto necessario:
/// - [id]: casuale, non derivato da nulla della sessione;
/// - [selfieBase64]: il selfie della persona segnalata com'era alla prima
///   segnalazione (già senza EXIF, vedi `SelfieValidator`): è ciò che si
///   giudica ("foto falsa", "inappropriata", "sembra minorenne");
/// - [reasons]: i motivi (lista chiusa `ReportReason`) con quante volte;
/// - [reportCount]: da quante sessioni diverse è stata segnalata;
/// - [autoClosed]: se è scattata la chiusura automatica;
/// - [createdAt]/[updatedAt]: arrotondati al minuto, in UTC.
///
/// **Mai**: posizione, chat, id interni, pseudonimi, segreti, profilo, IP
/// (nemmeno come hash: la deduplica delle segnalazioni la fa
/// `ModerationStore` in RAM finché la sessione è viva, il record non ne ha
/// bisogno). Nessun campo collega il record a un dispositivo o a un'altra
/// sessione.
class ModerationRecord {
  const ModerationRecord({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.reasons,
    required this.reportCount,
    required this.autoClosed,
    required this.selfieBase64,
  });

  factory ModerationRecord.fromJson(Map<String, dynamic> json) =>
      ModerationRecord(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        reasons: (json['reasons'] as Map<String, dynamic>).map(
          (reason, count) => MapEntry(reason, count as int),
        ),
        reportCount: json['reportCount'] as int,
        autoClosed: json['autoClosed'] as bool,
        selfieBase64: json['selfieBase64'] as String,
      );

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, int> reasons;
  final int reportCount;
  final bool autoClosed;
  final String selfieBase64;

  /// L'ora [time] arrotondata (per difetto) al minuto, in UTC: un orario al
  /// secondo aiuterebbe a incrociare il record con altri log.
  static DateTime roundToMinute(DateTime time) {
    final utc = time.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }

  /// Tutto il record, selfie compreso — solo dentro il file cifrato.
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'reasons': reasons,
    'reportCount': reportCount,
    'autoClosed': autoClosed,
    'selfieBase64': selfieBase64,
  };

  /// I metadati per la lista di `GET /admin/reports`: senza selfie (si
  /// scarica a parte), con la data in cui il record sarà cancellato.
  Map<String, dynamic> toMetadataJson({required Duration retention}) => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'expiresAt': createdAt.add(retention).toIso8601String(),
    'reasons': reasons,
    'reportCount': reportCount,
    'autoClosed': autoClosed,
    'hasSelfie': selfieBase64.isNotEmpty,
  };
}

/// Salva i [ModerationRecord] **cifrati a riposo** (AES-256-GCM), un file
/// per record in [directory], e li cancella da soli dopo [retention] (30
/// giorni da `createdAt`, vedi [purgeExpired]).
///
/// - **Chiave**: `MODERATION_KEY`, 32 byte in base64 (es. `openssl rand
///   -base64 32`). Senza (o non valida) i record **non vengono salvati**
///   ([isEnabled] è `false`, il motivo in [configurationProblem], loggato
///   all'avvio da `main.dart`): la moderazione in RAM (blocchi, soglie,
///   chiusura automatica) funziona lo stesso. Mai una chiave di ripiego.
/// - **Formato** di `<id>.rec`: `RMR1` + nonce (12 byte) + testo cifrato +
///   MAC (16 byte); i dati aggiuntivi autenticati sono l'id, quindi un file
///   rinominato (o scambiato con un altro) non si decifra.
/// - **Scrittura atomica** (file temporaneo + `rename`) e serializzata per
///   record: un salvataggio dopo l'altro, l'ultimo vince sempre.
class ModerationRecordStore {
  ModerationRecordStore({
    required this.directory,
    required List<int>? key,
    this.configurationProblem,
    this.retention = defaultRetention,
    DateTime Function()? now,
  }) : _key = key == null ? null : SecretKey(List.unmodifiable(key)),
       _now = now ?? DateTime.now;

  /// Configurazione da [environment] (`MODERATION_KEY`, `MODERATION_DIR`).
  factory ModerationRecordStore.fromEnvironment(
    Map<String, String> environment, {
    DateTime Function()? now,
  }) {
    final rawDir = environment[directoryEnvironmentVariable]?.trim() ?? '';
    final directory = Directory(rawDir.isEmpty ? defaultDirectory : rawDir);
    final rawKey = environment[keyEnvironmentVariable]?.trim() ?? '';
    if (rawKey.isEmpty) {
      return ModerationRecordStore(
        directory: directory,
        key: null,
        configurationProblem:
            '$keyEnvironmentVariable non impostata: i record di moderazione '
            'NON vengono salvati.',
        now: now,
      );
    }
    List<int>? key;
    try {
      key = base64Decode(rawKey);
    } on FormatException {
      key = null;
    }
    if (key == null || key.length != keyLength) {
      return ModerationRecordStore(
        directory: directory,
        key: null,
        configurationProblem:
            '$keyEnvironmentVariable non valida (servono $keyLength byte in '
            'base64): i record di moderazione NON vengono salvati.',
        now: now,
      );
    }
    return ModerationRecordStore(directory: directory, key: key, now: now);
  }

  static final ModerationRecordStore instance =
      ModerationRecordStore.fromEnvironment(Platform.environment);

  static const keyEnvironmentVariable = 'MODERATION_KEY';
  static const directoryEnvironmentVariable = 'MODERATION_DIR';
  static const defaultDirectory = 'moderation_records';
  static const defaultRetention = Duration(days: 30);
  static const keyLength = 32;
  static const _magic = [0x52, 0x4D, 0x52, 0x31]; // "RMR1"
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _extension = '.rec';

  final Directory directory;
  final Duration retention;

  /// Perché i record non vengono salvati, o `null` se è tutto a posto.
  final String? configurationProblem;
  final SecretKey? _key;
  final DateTime Function() _now;
  final AesGcm _algorithm = AesGcm.with256bits();
  final Map<String, Future<void>> _writes = {};
  Timer? _purgeTimer;
  bool _directoryReady = false;

  bool get isEnabled => _key != null;

  /// `true` se [id] ha la forma di un id di record (32 cifre esadecimali
  /// minuscole): va controllato **prima** di toccare il disco, così un id
  /// non può mai diventare un percorso (`../`).
  static bool isValidId(String id) => RegExp(r'^[0-9a-f]{32}$').hasMatch(id);

  File _fileFor(String id) =>
      File('${directory.path}${Platform.pathSeparator}$id$_extension');

  Future<void> _ensureDirectory() async {
    if (_directoryReady) return;
    await directory.create(recursive: true);
    if (!Platform.isWindows) {
      // Solo il processo del server deve poterla leggere. Best-effort: su
      // un filesystem che non lo permette resta com'è (i file sono comunque
      // cifrati).
      try {
        await Process.run('chmod', ['700', directory.path]);
      } catch (_) {}
    }
    _directoryReady = true;
  }

  /// Salva (o sostituisce) [record]. Senza chiave non fa nulla. I
  /// salvataggi dello stesso record sono messi in fila.
  Future<void> save(ModerationRecord record) {
    if (!isEnabled || !isValidId(record.id)) return Future.value();
    final previous = _writes[record.id] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => _write(record));
    _writes[record.id] = next;
    return next.whenComplete(() {
      if (identical(_writes[record.id], next)) _writes.remove(record.id);
    });
  }

  /// Aspetta che ogni salvataggio in corso sia finito (test, spegnimento).
  Future<void> flush() => Future.wait([
    for (final write in _writes.values) write.catchError((Object _) {}),
  ]);

  Future<void> _write(ModerationRecord record) async {
    await _ensureDirectory();
    final box = await _algorithm.encrypt(
      utf8.encode(jsonEncode(record.toJson())),
      secretKey: _key!,
      aad: utf8.encode(record.id),
    );
    final bytes = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    final file = _fileFor(record.id);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes.takeBytes(), flush: true);
    await temporary.rename(file.path);
  }

  /// Il record [id], o `null` se non esiste, l'id non è valido o il file
  /// non si decifra (chiave diversa, file manomesso).
  Future<ModerationRecord?> read(String id) async {
    if (!isEnabled || !isValidId(id)) return null;
    await _writes[id]?.catchError((Object _) {});
    final file = _fileFor(id);
    if (!await file.exists()) return null;
    return _decrypt(id, await file.readAsBytes());
  }

  Future<ModerationRecord?> _decrypt(String id, List<int> bytes) async {
    const header = 4 + _nonceLength;
    if (bytes.length < header + _macLength) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return null;
    }
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(
          bytes.sublist(header, bytes.length - _macLength),
          nonce: bytes.sublist(4, header),
          mac: Mac(bytes.sublist(bytes.length - _macLength)),
        ),
        secretKey: _key!,
        aad: utf8.encode(id),
      );
      final record = ModerationRecord.fromJson(
        jsonDecode(utf8.decode(clear)) as Map<String, dynamic>,
      );
      return record.id == id ? record : null;
    } catch (_) {
      return null;
    }
  }

  /// Tutti i record leggibili, dal più recente.
  Future<List<ModerationRecord>> list() async {
    if (!isEnabled || !await directory.exists()) return const [];
    final records = <ModerationRecord>[];
    for (final id in await _storedIds()) {
      final record = await read(id);
      if (record != null) records.add(record);
    }
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records;
  }

  Future<List<String>> _storedIds() async {
    final ids = <String>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith(_extension)) continue;
      final id = name.substring(0, name.length - _extension.length);
      if (isValidId(id)) ids.add(id);
    }
    return ids;
  }

  /// Cancella il record [id] (segnalazione risolta). `true` se c'era.
  Future<bool> delete(String id) async {
    if (!isValidId(id)) return false;
    await _writes[id]?.catchError((Object _) {});
    final file = _fileFor(id);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  /// Cancella i record più vecchi di [retention] (da `createdAt`). Un file
  /// che non si decifra (chiave cambiata, file rovinato) si giudica dalla
  /// sua data di modifica: nessun file resta per sempre solo perché non si
  /// riesce più a leggerlo. Funziona anche senza chiave (allora tutti i
  /// file si giudicano dalla data). Ritorna quanti ne ha cancellati.
  Future<int> purgeExpired() async {
    if (!await directory.exists()) return 0;
    final now = _now();
    var deleted = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('$_extension.tmp')) {
        // Resto di una scrittura interrotta.
        if (now.difference(await entity.lastModified()) > retention) {
          await entity.delete();
        }
        continue;
      }
      if (!name.endsWith(_extension)) continue;
      final id = name.substring(0, name.length - _extension.length);
      final record = isEnabled && isValidId(id)
          ? await _decrypt(id, await entity.readAsBytes())
          : null;
      final createdAt = record?.createdAt ?? await entity.lastModified();
      if (now.difference(createdAt) >= retention) {
        await entity.delete();
        deleted++;
      }
    }
    return deleted;
  }

  /// Avvia (se non già attivo) [purgeExpired] periodico. Un errore non esce
  /// mai dal timer (farebbe cadere il processo).
  void startPeriodicPurge({Duration interval = const Duration(hours: 1)}) {
    _purgeTimer ??= Timer.periodic(interval, (_) => unawaited(purgeSafely()));
  }

  /// [purgeExpired] senza eccezioni: gli errori finiscono nel log.
  Future<void> purgeSafely() async {
    try {
      await purgeExpired();
    } catch (error, stackTrace) {
      developer.log(
        'Pulizia dei record di moderazione fallita',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void stopPeriodicPurge() {
    _purgeTimer?.cancel();
    _purgeTimer = null;
  }
}
