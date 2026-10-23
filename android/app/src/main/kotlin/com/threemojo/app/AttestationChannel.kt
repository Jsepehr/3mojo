package com.threemojo.app

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Lato Android del canale `raen/attestation` (vedi
 * `attestation_data_source_impl.dart`): un token della **Play Integrity API,
 * Standard request**, legato al challenge del server con `requestHash`
 * (`hex(SHA-256(utf8(nonce)))`, calcolato in Dart).
 *
 * Il "provider" di token (`prepareIntegrityToken`, il passo lento in cui il
 * Play Store prepara il verdetto) si tiene in memoria finché vale e si
 * rifà una volta se Google lo dichiara scaduto. Non contiene e non produce
 * identificativi del dispositivo: è solo una cache del Play Store per questa
 * app. Nulla viene scritto su disco.
 *
 * TODO(attestation): funziona solo con il progetto Google Cloud collegato in
 * Play Console (numero in `AttestationConfig.googleCloudProjectNumber`) e
 * con l'app installata da Google Play (altrimenti il verdetto è
 * `UNRECOGNIZED_VERSION` e il server rifiuta).
 */
object AttestationChannel {
    private var provider: StandardIntegrityTokenProvider? = null
    private var providerProjectNumber: Long = 0

    fun register(messenger: BinaryMessenger, context: Context) {
        val manager = IntegrityManagerFactory.createStandard(context)
        MethodChannel(messenger, "raen/attestation").setMethodCallHandler { call, result ->
            if (call.method != "playIntegrityToken") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val requestHash = call.argument<String>("requestHash")
            val projectNumber = call.argument<Number>("cloudProjectNumber")?.toLong() ?: 0L
            if (requestHash.isNullOrEmpty() || projectNumber <= 0L) {
                result.error("BAD_ARGS", "requestHash o cloudProjectNumber mancante", null)
                return@setMethodCallHandler
            }
            requestToken(manager, projectNumber, requestHash, canRetry = true, result)
        }
    }

    private fun requestToken(
        manager: StandardIntegrityManager,
        projectNumber: Long,
        requestHash: String,
        canRetry: Boolean,
        result: MethodChannel.Result,
    ) {
        val cached = provider?.takeIf { providerProjectNumber == projectNumber }
        if (cached == null) {
            val prepare = PrepareIntegrityTokenRequest.builder()
                .setCloudProjectNumber(projectNumber)
                .build()
            manager.prepareIntegrityToken(prepare)
                .addOnSuccessListener { prepared ->
                    provider = prepared
                    providerProjectNumber = projectNumber
                    requestToken(manager, projectNumber, requestHash, canRetry = false, result)
                }
                .addOnFailureListener { e -> result.error("PREPARE_FAILED", e.toString(), null) }
            return
        }
        val request = StandardIntegrityTokenRequest.builder()
            .setRequestHash(requestHash)
            .build()
        cached.request(request)
            .addOnSuccessListener { response -> result.success(response.token()) }
            .addOnFailureListener { e ->
                // Provider scaduto o invalidato da Google: se ne prepara uno
                // nuovo, una volta sola.
                provider = null
                if (canRetry) {
                    requestToken(manager, projectNumber, requestHash, canRetry = false, result)
                } else {
                    result.error("REQUEST_FAILED", e.toString(), null)
                }
            }
    }
}
