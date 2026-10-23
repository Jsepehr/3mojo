import 'package:flutter/foundation.dart';

import '/core/config/attestation_config.dart';
import 'attestation_data_source.dart';
import 'attestation_data_source_fake_impl.dart';
import 'attestation_data_source_impl.dart';

/// Quella di questo build: la finta solo nei build di debug (a meno di
/// `--dart-define=ATTESTATION_NATIVE=true`), altrimenti App Attest / Play
/// Integrity veri — vedi [AttestationConfig.useFake].
AttestationDataSource defaultAttestationDataSource() =>
    AttestationConfig.useFake(debugBuild: kDebugMode)
    ? const AttestationDataSourceFakeImpl()
    : AttestationDataSourceImpl();
