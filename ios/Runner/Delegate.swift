import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class Delegate: FlutterAppDelegate {
  let engine = AVAudioEngine()
  let speaker = AVAudioPlayerNode()
  var format: AVAudioFormat?
  var explorer: Explorer?
  var playback: Playback?
  var links: FlutterMethodChannel?
  // A zephyron:// link the app was opened with, until Dart asks for it.
  var pending: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    let messenger = controller.binaryMessenger
    if let link = launchOptions?[.url] as? URL, link.scheme == "zephyron" {
      pending = link.absoluteString
    }
    let links = FlutterMethodChannel(name: "links", binaryMessenger: messenger)
    self.links = links
    links.setMethodCallHandler { [weak self] call, result in
      guard call.method == "initial" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pending)
      self?.pending = nil
    }

    FlutterMethodChannel(name: "media", binaryMessenger: messenger).setMethodCallHandler {
      call, result in
      guard let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      // A small JPEG of a video's first moments, made with the phone's own decoder.
      case "thumbnail":
        let width = arguments["width"] as? Int ?? 480
        DispatchQueue.global(qos: .userInitiated).async {
          let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = CGSize(width: width, height: width)
          let moment = CMTime(seconds: 0.5, preferredTimescale: 600)
          let bytes = (try? generator.copyCGImage(at: moment, actualTime: nil)).flatMap {
            UIImage(cgImage: $0).jpegData(compressionQuality: 0.7)
          }
          DispatchQueue.main.async {
            result(bytes.map { FlutterStandardTypedData(bytes: $0) })
          }
        }
      // A video's or a recording's length, and a video's upright size.
      case "probe":
        DispatchQueue.global(qos: .userInitiated).async {
          let asset = AVURLAsset(url: URL(fileURLWithPath: path))
          let seconds = asset.duration.seconds
          var width = 0
          var height = 0
          if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            width = Int(abs(size.width))
            height = Int(abs(size.height))
          }
          let facts = [
            "duration": seconds.isFinite ? Int(seconds * 1000) : 0,
            "width": width,
            "height": height,
          ]
          DispatchQueue.main.async { result(facts) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let explorer = Explorer(host: controller)
    self.explorer = explorer
    FlutterMethodChannel(name: "explorer", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in explorer.handle(call, result: result) }

    let channel = FlutterMethodChannel(name: "playback", binaryMessenger: messenger)
    if let textures = self.registrar(forPlugin: "Playback")?.textures() {
      let playback = Playback(textures: textures, channel: channel)
      self.playback = playback
      channel.setMethodCallHandler { call, result in playback.handle(call, result: result) }
    }

    // Notifications only ever say who wrote and how many messages there
    // are, never what they say.
    FlutterMethodChannel(name: "alerts", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        let center = UNUserNotificationCenter.current()
        let arguments = call.arguments as? [String: Any] ?? [:]
        let id = "zephyron-\(arguments["id"] as? Int ?? 0)"
        switch call.method {
        case "permit":
          center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
          result(nil)
        case "show":
          let content = UNMutableNotificationContent()
          content.title = arguments["title"] as? String ?? "Zephyron"
          content.body = arguments["text"] as? String ?? ""
          content.sound = .default
          center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
          result(nil)
        case "cancel":
          center.removeDeliveredNotifications(withIdentifiers: [id])
          result(nil)
        case "stand":
          // iOS gives no way to keep Tor running in the background.
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterMethodChannel(name: "share", binaryMessenger: messenger)
      .setMethodCallHandler { [weak controller] call, result in
        guard let controller = controller,
          let arguments = call.arguments as? [String: Any]
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        let items: [Any]
        switch call.method {
        case "text":
          items = [arguments["text"] as? String ?? ""]
        case "file":
          guard let path = arguments["path"] as? String else {
            result(nil)
            return
          }
          items = [URL(fileURLWithPath: path)]
        default:
          result(FlutterMethodNotImplemented)
          return
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let subject = arguments["subject"] as? String {
          sheet.setValue(subject, forKey: "subject")
        }
        // iPads show the sheet as a popover, which needs somewhere to point.
        sheet.popoverPresentationController?.sourceView = controller.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
          x: controller.view.bounds.midX,
          y: controller.view.bounds.midY,
          width: 0,
          height: 0
        )
        controller.present(sheet, animated: true)
        result(nil)
      }

    FlutterMethodChannel(name: "sound", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        let arguments = call.arguments as? [String: Any]
        switch call.method {
        // Starts a player for 16-bit mono audio at the given rate, converted
        // to the float format the engine mixes in.
        case "open":
          let rate = Double(arguments?["rate"] as? Int ?? 8000)
          try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth]
          )
          try? AVAudioSession.sharedInstance().setActive(true)
          let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)
          self.format = mono
          if self.speaker.engine == nil { self.engine.attach(self.speaker) }
          self.engine.connect(self.speaker, to: self.engine.mainMixerNode, format: mono)
          try? self.engine.start()
          self.speaker.play()
          result(nil)
        case "feed":
          if let data = (arguments?["pcm"] as? FlutterStandardTypedData)?.data,
            let format = self.format
          {
            let count = data.count / 2
            if count > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
            {
              buffer.frameLength = AVAudioFrameCount(count)
              let out = buffer.floatChannelData![0]
              data.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                for index in 0..<count {
                  out[index] = Float(samples[index]) / 32768
                }
              }
              self.speaker.scheduleBuffer(buffer, completionHandler: nil)
            }
          }
          result(nil)
        case "close":
          self.speaker.stop()
          self.engine.stop()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.scheme == "zephyron" else {
      return super.application(app, open: url, options: options)
    }
    if let links = links {
      links.invokeMethod("open", arguments: url.absoluteString)
    } else {
      pending = url.absoluteString
    }
    return true
  }
}
