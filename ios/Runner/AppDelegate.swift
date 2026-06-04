import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let media = FlutterMethodChannel(
        name: "zephyron/media",
        binaryMessenger: controller.binaryMessenger
      )
      media.setMethodCallHandler { call, result in
        guard call.method == "thumbnail",
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        let width = arguments["width"] as? Int ?? 480
        DispatchQueue.global(qos: .userInitiated).async {
          let bytes = AppDelegate.still(path: path, width: width)
          DispatchQueue.main.async {
            result(bytes.map { FlutterStandardTypedData(bytes: $0) })
          }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// A small JPEG of a video's first moments, made with the phone's own decoder.
  static func still(path: String, width: Int) -> Data? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: width, height: width)
    let moment = CMTime(seconds: 0.5, preferredTimescale: 600)
    guard let frame = try? generator.copyCGImage(at: moment, actualTime: nil) else {
      return nil
    }
    return UIImage(cgImage: frame).jpegData(compressionQuality: 0.7)
  }
}
