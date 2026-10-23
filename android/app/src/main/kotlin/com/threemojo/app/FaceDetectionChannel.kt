package com.threemojo.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.media.FaceDetector
import android.os.Handler
import android.os.Looper
import androidx.exifinterface.media.ExifInterface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Lato Android del canale `raen/face_detection` (vedi `face_detector_io.dart`):
 * `android.media.FaceDetector` del sistema operativo — tutto sul dispositivo,
 * nessuna libreria esterna, nessuna rete, nessuna telemetria. Risponde solo
 * "c'è almeno un volto sì/no"; non estrae né conserva nulla del volto.
 *
 * Contratto (metodo, argomento e risultato come il lato iOS in
 * `AppDelegate.swift`, che però non distingue `IMAGE_ERROR`):
 * - metodo `detectFace`, argomento `path` (file temporaneo scritto da Dart,
 *   che lo cancella a fine controllo);
 * - risultato `Boolean`;
 * - errori `BAD_ARGS` (manca `path`), `IMAGE_ERROR` (file non leggibile o
 *   non decodificabile), `DETECTION_ERROR` (errore durante il rilevamento,
 *   memoria esaurita compresa). Lato Dart ogni errore diventa
 *   `FaceCheckUnavailableFailure`.
 *
 * Il lavoro (decodifica, rotazione, rilevamento) gira su un thread dedicato:
 * mai sul main thread, che resta libero per Flutter. La risposta torna sul
 * main thread, come vuole `MethodChannel.Result`.
 *
 * Al posto di Google ML Kit (`com.google.mlkit:face-detection`), che
 * inviava a Google telemetria di uso e diagnostica. `FaceDetector` è un
 * rilevatore più vecchio e meno tollerante (volti molto girati o inclinati,
 * poca luce): i parametri sotto sono il punto da regolare dopo le prove su
 * telefoni veri.
 */
object FaceDetectionChannel {
    /**
     * Lato lungo massimo dell'immagine analizzata. `FaceDetector` costa in
     * proporzione ai pixel: un selfie da 12 MP ridotto a 800 px lascia
     * comunque un volto in primo piano largo centinaia di pixel.
     */
    private const val MAX_LONG_SIDE = 800

    /**
     * Quanti volti cercare al massimo. Ne basta uno, ma se il primo trovato è
     * troppo piccolo (vedi [MIN_FACE_WIDTH_RATIO]) gli altri possono valere.
     */
    private const val MAX_FACES = 4

    /**
     * Confidenza minima di un volto (0..1). Più bassa di
     * `FaceDetector.Face.CONFIDENCE_THRESHOLD` (0,4), la soglia che il sistema
     * stesso considera "buona": qui un falso negativo (selfie vero rifiutato,
     * l'utente non riesce ad andare online) costa più di un falso positivo
     * (il controllo è solo un filtro leggero contro foto senza persone, non
     * una verifica d'identità).
     */
    private const val MIN_CONFIDENCE = 0.3f

    /**
     * Larghezza minima del volto rispetto alla larghezza dell'immagine, come
     * l'opzione predefinita `minFaceSize = 0.1` di ML Kit usata prima: un
     * volto lontano sullo sfondo non conta come selfie.
     */
    private const val MIN_FACE_WIDTH_RATIO = 0.1f

    /**
     * `FaceDetector` dà solo la distanza tra gli occhi: la larghezza del
     * volto si stima come circa il doppio (per difetto — una testa vera è
     * circa 2,3 volte — così il filtro sulla dimensione è indulgente).
     */
    private const val FACE_WIDTH_PER_EYES_DISTANCE = 2f

    private val executor: ExecutorService by lazy {
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "raen-face-detection").apply { isDaemon = true }
        }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
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
            executor.execute {
                var hasFace = false
                var errorCode: String? = null
                var errorMessage: String? = null
                try {
                    hasFace = detectFace(path)
                } catch (e: ImageException) {
                    errorCode = "IMAGE_ERROR"
                    errorMessage = e.message
                } catch (e: Exception) {
                    errorCode = "DETECTION_ERROR"
                    errorMessage = e.toString()
                } catch (e: OutOfMemoryError) {
                    errorCode = "DETECTION_ERROR"
                    errorMessage = e.toString()
                }
                mainHandler.post {
                    if (errorCode == null) {
                        result.success(hasFace)
                    } else {
                        result.error(errorCode, errorMessage, null)
                    }
                }
            }
        }
    }

    private class ImageException(message: String) : Exception(message)

    private fun detectFace(path: String): Boolean {
        val upright = loadUprightBitmap(path)
        try {
            val faces = arrayOfNulls<FaceDetector.Face>(MAX_FACES)
            val found = FaceDetector(upright.width, upright.height, MAX_FACES)
                .findFaces(upright, faces)
            val minFaceWidth = upright.width * MIN_FACE_WIDTH_RATIO
            return faces.take(found).any { face ->
                face != null &&
                    face.confidence() >= MIN_CONFIDENCE &&
                    face.eyesDistance() * FACE_WIDTH_PER_EYES_DISTANCE >= minFaceWidth
            }
        } finally {
            upright.recycle()
        }
    }

    /**
     * Legge il file come lo vedrebbe una persona: orientamento EXIF applicato
     * (il sensore frontale salva spesso i pixel ruotati di 90° con un tag che
     * dice come raddrizzarli; `FaceDetector` trova solo volti dritti), lato
     * lungo al più [MAX_LONG_SIDE], larghezza pari e `RGB_565`, i due
     * requisiti di `FaceDetector`.
     *
     * Memoria: la decodifica usa già un `inSampleSize` (mai l'immagine a
     * piena risoluzione in RAM); il bitmap intermedio è riciclato appena
     * disegnato in quello finale, che ricicla il chiamante.
     */
    private fun loadUprightBitmap(path: String): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw ImageException("Immagine non leggibile")
        }

        var sampleSize = 1
        val longSide = max(bounds.outWidth, bounds.outHeight)
        while (longSide / (sampleSize * 2) >= MAX_LONG_SIDE) sampleSize *= 2
        val decoded = BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.RGB_565
            },
        ) ?: throw ImageException("Immagine non decodificabile")

        try {
            val matrix = orientationMatrix(readExifOrientation(path))
            val scale = MAX_LONG_SIDE.toFloat() / max(decoded.width, decoded.height)
            if (scale < 1f) matrix.postScale(scale, scale)
            val target = RectF(0f, 0f, decoded.width.toFloat(), decoded.height.toFloat())
            matrix.mapRect(target)
            matrix.postTranslate(-target.left, -target.top)

            // FaceDetector vuole una larghezza pari.
            val width = target.width().roundToInt() and 1.inv()
            val height = target.height().roundToInt()
            if (width < 2 || height < 1) throw ImageException("Immagine troppo piccola")

            val upright = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)
            Canvas(upright).drawBitmap(decoded, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
            return upright
        } finally {
            decoded.recycle()
        }
    }

    /** Orientamento EXIF; se manca o non si legge, l'immagine è già dritta. */
    private fun readExifOrientation(path: String): Int = try {
        ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
    } catch (e: Exception) {
        ExifInterface.ORIENTATION_NORMAL
    }

    /** Trasformazione che raddrizza i pixel secondo l'orientamento EXIF. */
    private fun orientationMatrix(orientation: Int): Matrix = Matrix().apply {
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                setRotate(180f)
                postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                setRotate(90f)
                postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                setRotate(-90f)
                postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
        }
    }
}
