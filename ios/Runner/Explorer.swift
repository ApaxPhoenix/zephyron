import Flutter
import MobileCoreServices
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Picks photos, videos and files with the system's own pickers, and takes
/// photos with the camera, without a library. Whatever is picked is copied
/// into the outbox, which the app wipes when the vault locks; photos are
/// scaled down and turned upright on the way, except GIFs.
final class Explorer: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
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

  /// Copies [source] into the outbox. Must run before a picker deletes it.
  func keep(_ source: URL, name: String) -> [String: Any]? {
    let safe = Explorer.clean(name)
    let target = Explorer.outbox().appendingPathComponent("picked-\(UUID().uuidString)-\(safe)")
    do {
      try FileManager.default.copyItem(at: source, to: target)
    } catch {
      return nil
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
    var picked: [String: Any] = ["path": target.path, "name": safe, "size": size]
    if #available(iOS 14, *) {
      picked["mime"] = UTType(filenameExtension: (safe as NSString).pathExtension)?.preferredMIMEType
    }
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
    let base = Explorer.clean((name as NSString).deletingPathExtension)
    let target = Explorer.outbox().appendingPathComponent("picked-\(UUID().uuidString)-\(base).jpg")
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

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt links: [URL]) {
    guard let link = links.first else {
      finish(nil)
      return
    }
    finish(keep(link, name: link.lastPathComponent))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }
}

@available(iOS 14, *)
extension Explorer: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let item = results.first?.itemProvider else {
      finish(nil)
      return
    }
    let name = item.suggestedName ?? "picked"
    if item.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
      item.loadFileRepresentation(forTypeIdentifier: UTType.gif.identifier) { link, _ in
        self.finish(link.flatMap { self.keep($0, name: "\(name).gif") })
      }
    } else if item.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
      item.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { link, _ in
        self.finish(
          link.flatMap {
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
