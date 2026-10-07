import Flutter
import UIKit
import Vision
import ImageIO

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
    let channel = FlutterMethodChannel(
      name: "es.tallerflow/local_text",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "IMAGE_INVALID", message: "Imagen privada no disponible", details: nil))
        return
      }
      let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
      let root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().standardizedFileURL.path + "/"
      guard url.path.hasPrefix(root),
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? NSNumber, size.intValue > 0, size.intValue <= 16777216 else {
        result(FlutterError(code: "IMAGE_INVALID", message: "Imagen privada no disponible", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "TallerFlowCapture", code: 1)
          }
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
          let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
          let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
          let request = VNRecognizeTextRequest()
          request.recognitionLevel = .accurate
          request.recognitionLanguages = ["es-ES", "en-US"]
          // Technical identifiers must reach the human review without spelling
          // corrections intended for prose.
          request.usesLanguageCorrection = false
          try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
          let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
          DispatchQueue.main.async {
            if text.utf16.count <= 4000 { result(text) }
            else { result(FlutterError(code: "TEXT_LIMIT", message: "Captura demasiado extensa", details: nil)) }
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "READ_FAILED", message: "No se pudo leer la imagen", details: nil))
          }
        }
      }
    }
  }
}
