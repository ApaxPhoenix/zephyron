import AVFoundation
import Flutter
import MobileCoreServices
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate {
  let engine = AVAudioEngine()
  let player = AVAudioPlayerNode()
  var format: AVAudioFormat?
  var picking: Picking?
  var players: Players?

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
        guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        switch call.method {
        case "thumbnail":
          let width = arguments["width"] as? Int ?? 480
          DispatchQueue.global(qos: .userInitiated).async {
            let bytes = AppDelegate.still(path: path, width: width)
            DispatchQueue.main.async {
              result(bytes.map { FlutterStandardTypedData(bytes: $0) })
            }
          }
        case "probe":
          DispatchQueue.global(qos: .userInitiated).async {
            let facts = AppDelegate.probe(path: path)
            DispatchQueue.main.async { result(facts) }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let picking = Picking(host: controller)
      self.picking = picking
      FlutterMethodChannel(name: "zephyron/picker", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { call, result in picking.handle(call, result: result) }

      let playback = FlutterMethodChannel(
        name: "zephyron/player",
        binaryMessenger: controller.binaryMessenger
      )
      if let textures = self.registrar(forPlugin: "ZephyronPlayer")?.textures() {
        let players = Players(textures: textures, channel: playback)
        self.players = players
        playback.setMethodCallHandler { call, result in players.handle(call, result: result) }
      }

      FlutterMethodChannel(name: "zephyron/share", binaryMessenger: controller.binaryMessenger)
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

  /// A video's or a recording's length, and a video's upright size.
  static func probe(path: String) -> [String: Int] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let seconds = asset.duration.seconds
    var width = 0
    var height = 0
    if let track = asset.tracks(withMediaType: .video).first {
      let size = track.naturalSize.applying(track.preferredTransform)
      width = Int(abs(size.width))
      height = Int(abs(size.height))
    }
    return [
      "duration": seconds.isFinite ? Int(seconds * 1000) : 0,
      "width": width,
      "height": height,
    ]
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

/// Picks photos, videos and files with the system's own pickers, and takes
/// photos with the camera, without a library. Whatever is picked is copied
/// into the outbox, which the app wipes when the vault locks; photos are
/// scaled down and turned upright on the way, except GIFs.
final class Picking: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
  UIDocumentPickerDelegate
{
  weak var host: UIViewController?
  var pending: FlutterResult?
  var limit: CGFloat = 2560
  var quality: CGFloat = 0.88

  init(host: UIViewController) {
    self.host = host
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "A picker is already open", details: nil))
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    limit = CGFloat(arguments["limit"] as? Int ?? 2560)
    quality = CGFloat(arguments["quality"] as? Int ?? 88) / 100
    let shown: UIViewController
    switch call.method {
    case "photo", "video":
      let photo = call.method == "photo"
      if #available(iOS 14, *) {
        var configuration = PHPickerConfiguration()
        configuration.filter = photo ? .images : .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        shown = picker
      } else {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = [photo ? kUTTypeImage as String : kUTTypeMovie as String]
        picker.delegate = self
        shown = picker
      }
    case "camera":
      guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
        result(FlutterError(code: "missing", message: "This phone has no camera", details: nil))
        return
      }
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      if arguments["front"] as? Bool == true, UIImagePickerController.isCameraDeviceAvailable(.front) {
        picker.cameraDevice = .front
      }
      picker.delegate = self
      shown = picker
    case "file":
      let type = arguments["type"] as? String ?? "*/*"
      let picker: UIDocumentPickerViewController
      if #available(iOS 14, *) {
        let types: [UTType] =
          type == "audio/*" ? [.audio] : type == "image/gif" ? [.gif] : [.item]
        picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
      } else {
        let types =
          type == "audio/*"
          ? [kUTTypeAudio as String] : type == "image/gif" ? [kUTTypeGIF as String] : [kUTTypeItem as String]
        picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
      }
      picker.delegate = self
      shown = picker
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    pending = result
    host?.present(shown, animated: true)
  }

  func finish(_ value: Any?) {
    DispatchQueue.main.async {
      self.pending?(value)
      self.pending = nil
    }
  }

  static func outbox() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "outbox", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  static func clean(_ name: String) -> String {
    name.replacingOccurrences(of: "[^A-Za-z0-9_.\\- ]", with: "_", options: .regularExpression)
  }

  static func mime(_ name: String) -> String? {
    if #available(iOS 14, *) {
      return UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType
    }
    return nil
  }

  /// Copies [source] into the outbox. Must run before a picker deletes it.
  func keep(_ source: URL, name: String) -> [String: Any]? {
    let safe = Picking.clean(name)
    let target = Picking.outbox().appendingPathComponent("picked-\(UUID().uuidString)-\(safe)")
    do {
      try FileManager.default.copyItem(at: source, to: target)
    } catch {
      return nil
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
    var picked: [String: Any] = ["path": target.path, "name": safe, "size": size]
    picked["mime"] = Picking.mime(safe)
    return picked
  }

  /// Scales [image] to the limit, drawing it upright, and keeps it as a JPEG.
  func save(_ image: UIImage, name: String) -> [String: Any]? {
    let width = image.size.width * image.scale
    let height = image.size.height * image.scale
    let factor = min(1, limit / max(width, height, 1))
    let size = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    guard let data = upright.jpegData(compressionQuality: quality) else { return nil }
    let base = Picking.clean((name as NSString).deletingPathExtension)
    let target = Picking.outbox().appendingPathComponent("picked-\(UUID().uuidString)-\(base).jpg")
    do {
      try data.write(to: target)
    } catch {
      return nil
    }
    return ["path": target.path, "name": "\(base).jpg", "mime": "image/jpeg", "size": data.count]
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    if let movie = info[.mediaURL] as? URL {
      finish(keep(movie, name: movie.lastPathComponent))
      return
    }
    guard let image = info[.originalImage] as? UIImage else {
      finish(nil)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      self.finish(self.save(image, name: "photo"))
    }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    finish(nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      finish(nil)
      return
    }
    finish(keep(url, name: url.lastPathComponent))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }
}

@available(iOS 14, *)
extension Picking: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let item = results.first?.itemProvider else {
      finish(nil)
      return
    }
    let name = item.suggestedName ?? "picked"
    if item.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
      item.loadFileRepresentation(forTypeIdentifier: UTType.gif.identifier) { url, _ in
        self.finish(url.flatMap { self.keep($0, name: "\(name).gif") })
      }
    } else if item.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
      item.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
        self.finish(
          url.flatMap {
            self.keep($0, name: "\(name).\($0.pathExtension.isEmpty ? "mov" : $0.pathExtension)")
          })
      }
    } else if item.canLoadObject(ofClass: UIImage.self) {
      item.loadObject(ofClass: UIImage.self) { object, _ in
        self.finish((object as? UIImage).flatMap { self.save($0, name: name) })
      }
    } else {
      finish(nil)
    }
  }
}

/// Hands Flutter the newest frame of a playing video.
final class Screen: NSObject, FlutterTexture {
  let output: AVPlayerItemVideoOutput

  init(output: AVPlayerItemVideoOutput) {
    self.output = output
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let time = output.itemTime(forHostTime: CACurrentMediaTime())
    guard output.hasNewPixelBuffer(forItemTime: time),
      let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
    else { return nil }
    return Unmanaged.passRetained(buffer)
  }
}

/// Tells Flutter on every screen refresh that a video may have a new frame.
final class Ticker: NSObject {
  weak var textures: FlutterTextureRegistry?
  let texture: Int64

  init(textures: FlutterTextureRegistry, texture: Int64) {
    self.textures = textures
    self.texture = texture
  }

  @objc func tick() {
    textures?.textureFrameAvailable(texture)
  }
}

/// Plays voice messages, podcast episodes and videos with AVPlayer. A video
/// draws into a Flutter texture.
final class Players: NSObject {
  struct Entry {
    let player: AVPlayer
    let texture: Int64?
    let screen: Screen?
    let link: CADisplayLink?
    let observer: NSObjectProtocol
  }

  let textures: FlutterTextureRegistry
  let channel: FlutterMethodChannel
  var players: [Int: Entry] = [:]

  init(textures: FlutterTextureRegistry, channel: FlutterMethodChannel) {
    self.textures = textures
    self.channel = channel
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any], let id = arguments["id"] as? Int else {
      result(FlutterError(code: "id", message: "Every call names its player", details: nil))
      return
    }
    switch call.method {
    case "open":
      open(
        id: id, path: arguments["path"] as? String, video: arguments["video"] as? Bool ?? false,
        result: result)
    case "play":
      players[id]?.player.play()
      result(nil)
    case "pause":
      players[id]?.player.pause()
      result(nil)
    case "seek":
      let at = arguments["at"] as? Int ?? 0
      players[id]?.player.seek(
        to: CMTime(value: CMTimeValue(at), timescale: 1000), toleranceBefore: .zero,
        toleranceAfter: .zero)
      result(nil)
    case "position":
      let seconds = players[id]?.player.currentTime().seconds ?? 0
      result(seconds.isFinite ? Int(seconds * 1000) : 0)
    case "close":
      close(id)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func open(id: Int, path: String?, video: Bool, result: @escaping FlutterResult) {
    guard let path = path else {
      result(FlutterError(code: "path", message: "Nothing to play", details: nil))
      return
    }
    close(id)
    let session = AVAudioSession.sharedInstance()
    // A call keeps its own audio setup; anything else plays like media.
    if session.category != .playAndRecord {
      try? session.setCategory(.playback, mode: .default)
    }
    try? session.setActive(true)
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let item = AVPlayerItem(asset: asset)
    var screen: Screen?
    var texture: Int64?
    var link: CADisplayLink?
    if video {
      let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      ])
      item.add(output)
      let painted = Screen(output: output)
      let registered = textures.register(painted)
      let ticker = Ticker(textures: textures, texture: registered)
      let display = CADisplayLink(target: ticker, selector: #selector(Ticker.tick))
      display.add(to: .main, forMode: .common)
      screen = painted
      texture = registered
      link = display
    }
    let player = AVPlayer(playerItem: item)
    let observer = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
    ) { [weak self] _ in
      self?.players[id]?.player.seek(to: .zero)
      self?.channel.invokeMethod("done", arguments: ["id": id])
    }
    players[id] = Entry(
      player: player, texture: texture, screen: screen, link: link, observer: observer)
    asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) {
      DispatchQueue.main.async {
        let seconds = asset.duration.seconds
        var width = 0
        var height = 0
        var rotation = 0
        if let track = asset.tracks(withMediaType: .video).first {
          width = Int(abs(track.naturalSize.width))
          height = Int(abs(track.naturalSize.height))
          // Frames come out as stored, so Flutter turns them upright.
          let turn = track.preferredTransform
          let degrees = Int((atan2(Double(turn.b), Double(turn.a)) * 180 / Double.pi).rounded())
          rotation = (degrees % 360 + 360) % 360
        }
        var facts: [String: Any] = [
          "duration": seconds.isFinite ? Int(seconds * 1000) : 0,
          "width": width,
          "height": height,
          "rotation": rotation,
        ]
        if let texture = texture { facts["texture"] = texture }
        result(facts)
      }
    }
  }

  func close(_ id: Int) {
    guard let entry = players.removeValue(forKey: id) else { return }
    entry.player.pause()
    entry.link?.invalidate()
    NotificationCenter.default.removeObserver(entry.observer)
    if let texture = entry.texture { textures.unregisterTexture(texture) }
    entry.player.replaceCurrentItem(with: nil)
  }
}

