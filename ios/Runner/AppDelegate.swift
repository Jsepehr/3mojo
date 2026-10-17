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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FaceDetection") {
      FaceDetectionChannel.register(with: registrar.messenger())
    }
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
