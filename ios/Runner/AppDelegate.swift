import Flutter
import ImageIO
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    PrivacyCover.install()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FaceDetection") {
      FaceDetectionChannel.register(with: registrar.messenger())
    }
  }
}

/// Copre l'app con il colore del brand quando la scena **va in background**
/// e la scopre quando torna in primo piano. iOS scatta lo snapshot per il
/// selettore delle app **dopo** `didEnterBackground`: così quella scheda non
/// contiene selfie altrui, distanze o la chat.
///
/// Non si copre già a `willDeactivate`: la scena diventa inattiva anche
/// dietro ai dialoghi di sistema (permesso posizione/fotocamera, Face ID,
/// chiamata in arrivo, centro di controllo), e lo schermo diventerebbe blu
/// pieno proprio mentre l'utente deve leggere cosa sta concedendo. Il
/// prezzo: durante il gesto del multitasking, prima che l'app vada davvero
/// in background, si vede ancora il contenuto vivo.
///
/// Su iOS gli screenshot non si possono bloccare (a differenza di
/// `FLAG_SECURE` su Android): questo protegge solo lo snapshot del multitasking.
///
/// Ascolta le notifiche di `UIScene` invece dei callback di `UIApplication`:
/// l'app usa il ciclo di vita a scene (`FlutterSceneDelegate` in Info.plist),
/// dove i callback dell'app non vengono più chiamati. Nessuna sottoclasse di
/// `FlutterSceneDelegate` da mantenere.
enum PrivacyCover {
  /// Tag per ritrovare la copertura tra le subview della finestra.
  private static let coverTag = 0x3A0E5
  /// Blu primario del tema (`AppTheme`, 0xFF0236B3).
  private static let brandColor = UIColor(red: 0x02 / 255.0, green: 0x36 / 255.0, blue: 0xB3 / 255.0, alpha: 1)
  private static var installed = false

  static func install() {
    guard !installed else { return }
    installed = true
    let center = NotificationCenter.default
    center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { note in
      guard let scene = note.object as? UIWindowScene else { return }
      scene.windows.forEach(PrivacyCover.cover)
    }
    // Si scopre già a `willEnterForeground` (l'animazione di ritorno mostra
    // ancora lo snapshot coperto, poi il contenuto vivo); `didActivate` è
    // una sicurezza in più, innocua se non c'è nulla da togliere.
    for name in [UIScene.willEnterForegroundNotification, UIScene.didActivateNotification] {
      center.addObserver(forName: name, object: nil, queue: .main) { note in
        guard let scene = note.object as? UIWindowScene else { return }
        scene.windows.forEach(PrivacyCover.uncover)
      }
    }
  }

  private static func cover(_ window: UIWindow) {
    if let existing = window.viewWithTag(coverTag) {
      window.bringSubviewToFront(existing)
      return
    }
    let view = UIView(frame: window.bounds)
    view.tag = coverTag
    view.backgroundColor = brandColor
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.isUserInteractionEnabled = false
    window.addSubview(view)
  }

  private static func uncover(_ window: UIWindow) {
    window.viewWithTag(coverTag)?.removeFromSuperview()
  }
}

/// Lato iOS del canale `raen/face_detection` (vedi `face_detector_io.dart`):
/// Apple Vision sul dispositivo, nessuna foto lascia il telefono. Al posto di
/// Google ML Kit perché i suoi Pod escludono arm64 dal simulatore iOS.
enum FaceDetectionChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "raen/face_detection", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "detectFace" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "path mancante", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let reply: Any
        do {
          reply = try detectFace(atPath: path)
        } catch {
          reply = FlutterError(code: "DETECTION_ERROR", message: error.localizedDescription, details: nil)
        }
        DispatchQueue.main.async { result(reply) }
      }
    }
  }

  private static func detectFace(atPath path: String) throws -> Bool {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw NSError(domain: "FaceDetection", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Immagine non leggibile: \(path)"])
    }
    // Vision non legge da sé l'orientamento EXIF: senza, una foto scattata
    // in verticale verrebbe analizzata ruotata e il volto non trovato.
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let exif = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let orientation = CGImagePropertyOrientation(rawValue: exif) ?? .up

    let request = VNDetectFaceRectanglesRequest()
    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
    return !(request.results ?? []).isEmpty
  }
}
