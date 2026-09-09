import AVFoundation
import Flutter
import UIKit

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
final class Playback: NSObject {
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
      guard let path = arguments["path"] as? String else {
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
      if arguments["video"] as? Bool ?? false {
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

  func close(_ id: Int) {
    guard let entry = players.removeValue(forKey: id) else { return }
    entry.player.pause()
    entry.link?.invalidate()
    NotificationCenter.default.removeObserver(entry.observer)
    if let texture = entry.texture { textures.unregisterTexture(texture) }
    entry.player.replaceCurrentItem(with: nil)
  }
}
