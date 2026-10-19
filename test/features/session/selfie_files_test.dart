import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/core/usecases/usecase.dart';
import 'package:threemojo_app/features/session/data/datasources/face_detector_io.dart'
    as face_detector;
import 'package:threemojo_app/features/session/data/datasources/selfie_local_data_source_impl.dart';
import 'package:threemojo_app/features/session/data/repositories/selfie_repository_impl.dart';
import 'package:threemojo_app/features/session/domain/usecases/discard_selfie_files_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/end_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/flip_selfie_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/take_selfie_usecase.dart';

import '../../support/fake_repositories.dart';

const _uuid = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

/// Simula `image_picker`: scrive uno scatto in [directory] (come la cache
/// dell'app su Android) e ne ritorna il percorso.
class _FakeCamera {
  _FakeCamera(this.directory);

  final Directory directory;
  int shots = 0;

  File get lastFile => File('${directory.path}/$_uuid$shots.jpg');

  Future<XFile?> shoot() async {
    shots++;
    await lastFile.writeAsBytes([0xFF, 0xD8, shots, 0xFF, 0xD9]);
    return XFile(lastFile.path);
  }
}

void main() {
  late Directory cache;
  late _FakeCamera camera;
  late SelfieLocalDataSourceImpl dataSource;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('raen_selfie_test_');
    camera = _FakeCamera(cache);
    dataSource = SelfieLocalDataSourceImpl(pickImage: camera.shoot);
  });

  tearDown(() async {
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  List<String> filesIn(Directory dir) =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  group('selfie on disk', () {
    test(
      'the camera file is read and deleted at once: only bytes remain',
      () async {
        final bytes = await dataSource.takeSelfie();

        expect(bytes, [0xFF, 0xD8, 1, 0xFF, 0xD9]);
        expect(filesIn(cache), isEmpty);
      },
    );

    test('every retake also removes what an earlier shot left behind (e.g. '
        "the original image_picker didn't delete), but nothing else", () async {
      await File(
        '${cache.path}/scaled_image_picker_$_uuid.jpg',
      ).writeAsBytes([1]);
      await File('${cache.path}/$_uuid.jpg').writeAsBytes([1]);
      await File('${cache.path}/fonts.cache').writeAsBytes([1]);

      await dataSource.takeSelfie();
      await File('${cache.path}/image_picker_$_uuid.jpg').writeAsBytes([1]);
      await dataSource.takeSelfie();

      expect(filesIn(cache), ['fonts.cache']);
    });

    test('a cancelled shot leaves nothing to clean and returns null', () async {
      final ds = SelfieLocalDataSourceImpl(pickImage: () async => null);

      expect(await ds.takeSelfie(), isNull);
    });

    test('after End no selfie file is left on the phone, even one written '
        'after the last shot (app killed mid-shot)', () async {
      final repository = SelfieRepositoryImpl(dataSource);
      await TakeSelfieUseCase(repository)(const NoParams());
      await File('${cache.path}/$_uuid-leftover.jpg').writeAsBytes([1]);
      await File('${cache.path}/${_uuid}42.jpg').writeAsBytes([1]);

      final sessions = FakeSessionRepository(current: testSession('s1'));
      await EndSessionUseCase(
        repository: sessions,
        teardownSteps: [DiscardSelfieFilesUseCase(repository)],
      )(const NoParams());

      expect(filesIn(cache), ['$_uuid-leftover.jpg']);
      expect(sessions.current, isNull);
    });

    test('a camera error becomes SelfieCaptureFailure', () async {
      final repository = SelfieRepositoryImpl(
        SelfieLocalDataSourceImpl(
          pickImage: () async => throw Exception('no_available_camera'),
        ),
      );

      final result = await TakeSelfieUseCase(repository)(const NoParams());

      expect(result.getLeft().toNullable(), isA<SelfieCaptureFailure>());
    });
  });

  group('face check temporary file', () {
    final selfie = Uint8List.fromList([0xFF, 0xD8, 7, 0xFF, 0xD9]);

    test('exists only while the native check runs', () async {
      late String seenPath;
      late List<int> seenBytes;

      final hasFace = await face_detector.detectFace(
        selfie,
        detectAtPath: (path) async {
          seenPath = path;
          seenBytes = await File(path).readAsBytes();
          return true;
        },
      );

      expect(hasFace, isTrue);
      expect(seenBytes, selfie);
      expect(File(seenPath).existsSync(), isFalse);
      expect(File(seenPath).parent.existsSync(), isFalse);
    });

    test('is deleted even when the native check fails', () async {
      late String seenPath;

      await expectLater(
        face_detector.detectFace(
          selfie,
          detectAtPath: (path) async {
            seenPath = path;
            throw StateError('channel down');
          },
        ),
        throwsStateError,
      );
      expect(File(seenPath).parent.existsSync(), isFalse);
    });
  });

  group('flip', () {
    test('applies the EXIF orientation before mirroring and drops the EXIF '
        'data, so a rotated photo is not flipped upside down', () {
      final photo = img.Image(width: 40, height: 20);
      photo.exif.imageIfd['Orientation'] = img.IfdValueShort(6);
      photo.exif.imageIfd['Make'] = img.IfdValueAscii('PhoneMaker');
      final original = Uint8List.fromList(img.encodeJpg(photo));

      final flippedBytes = flipSelfieBytes(original);
      final flipped = img.decodeJpg(flippedBytes)!;

      // Raddrizzata (orientamento 6 = 90°) e poi ribaltata: 20×40, e
      // nessun metadato rimasto.
      expect(flipped.width, 20);
      expect(flipped.height, 40);
      expect(flipped.exif.isEmpty, isTrue);
    });

    test('bytes that are not an image come back unchanged', () {
      final garbage = Uint8List.fromList([1, 2, 3]);

      expect(flipSelfieBytes(garbage), garbage);
    });
  });

  test('the flip use case refuses an empty selfie', () async {
    final result = await FlipSelfieUseCase(SelfieRepositoryImpl(dataSource))(
      Uint8List(0),
    );

    expect(result.getLeft().toNullable(), isA<SelfieMissingFailure>());
  });
}
