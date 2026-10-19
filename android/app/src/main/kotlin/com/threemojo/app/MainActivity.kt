package com.threemojo.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE su tutta l'app, non per schermata: niente screenshot,
        // niente registrazione schermo/cast, e l'anteprima nel multitasking
        // resta nera. Quasi ogni pagina mostra selfie di altre persone, la
        // loro distanza o la chat — e l'app ha una sola Activity Flutter,
        // quindi "per schermata" vorrebbe dire un canale nativo che accende
        // e spegne il flag a ogni cambio di rotta: più codice e una finestra
        // di tempo (tra navigazione e chiamata al canale) in cui lo snapshot
        // del multitasking può già contenere il contenuto da proteggere.
        // Impostato prima di super.onCreate, così vale fin dal primo frame.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FaceDetectionChannel.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
    }
}
