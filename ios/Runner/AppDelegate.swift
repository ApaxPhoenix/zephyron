import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  let engine = AVAudioEngine()
  let player = AVAudioPlayerNode()
  var format: AVAudioFormat?

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
    if let controller = window?.rootViewController as? FlutterViewController {
      let sound = FlutterMethodChannel(
        name: "zephyron/sound",
        binaryMessenger: controller.binaryMessenger
      )
      sound.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "open":
          let rate = (call.arguments as? [String: Any])?["rate"] as? Int ?? 8000
          self.open(rate: Double(rate))
          result(nil)
        case "feed":
          if let data = (call.arguments as? [String: Any])?["pcm"] as? FlutterStandardTypedData {
            self.feed(data.data)
          }
          result(nil)
        case "close":
          self.player.stop()
          self.engine.stop()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Starts a player for 16-bit mono audio at the given rate, converted to
  /// the float format the engine mixes in.
  func open(rate: Double) {
    try? AVAudioSession.sharedInstance().setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetooth]
    )
    try? AVAudioSession.sharedInstance().setActive(true)
    let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)
    format = mono
    if player.engine == nil { engine.attach(player) }
    engine.connect(player, to: engine.mainMixerNode, format: mono)
    try? engine.start()
    player.play()
  }

  func feed(_ data: Data) {
    guard let format = format else { return }
    let count = data.count / 2
    guard count > 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
    else { return }
    buffer.frameLength = AVAudioFrameCount(count)
    let out = buffer.floatChannelData![0]
    data.withUnsafeBytes { raw in
      let samples = raw.bindMemory(to: Int16.self)
      for index in 0..<count {
        out[index] = Float(samples[index]) / 32768
      }
    }
    player.scheduleBuffer(buffer, completionHandler: nil)
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
