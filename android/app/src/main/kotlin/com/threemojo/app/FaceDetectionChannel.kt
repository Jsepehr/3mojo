package com.threemojo.app

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Lato Android del canale `raen/face_detection` (vedi `face_detector_io.dart`):
 * Google ML Kit sul dispositivo, nessuna foto lascia il telefono.
 * Stesse opzioni predefinite (modalità veloce, volto minimo 10%) e stessa
 * lettura del file (rotazione EXIF inclusa) del plugin
 * `google_mlkit_face_detection` usato in precedenza.
 */
object FaceDetectionChannel {
    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, "raen/face_detection").setMethodCallHandler { call, result ->
            if (call.method != "detectFace") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("BAD_ARGS", "path mancante", null)
                return@setMethodCallHandler
            }
            val image = try {
                InputImage.fromFilePath(context, Uri.fromFile(File(path)))
            } catch (e: Exception) {
                result.error("IMAGE_ERROR", e.toString(), null)
                return@setMethodCallHandler
            }
            val detector = FaceDetection.getClient(FaceDetectorOptions.Builder().build())
            detector.process(image)
                .addOnSuccessListener { faces -> result.success(faces.isNotEmpty()) }
                .addOnFailureListener { e -> result.error("DETECTION_ERROR", e.toString(), null) }
                .addOnCompleteListener { detector.close() }
        }
    }
}
