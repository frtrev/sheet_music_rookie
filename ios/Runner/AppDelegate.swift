import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let incomingFileChannelName = "sheet_music_rookie/incoming_file"
  private var incomingFileChannel: FlutterMethodChannel?
  private var pendingFilePath: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "MusicXMLIncomingFile"
    ) else { return }
    incomingFileChannel = FlutterMethodChannel(
      name: incomingFileChannelName,
      binaryMessenger: registrar.messenger()
    )
    incomingFileChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pendingFilePath)
      self?.pendingFilePath = nil
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if captureMusicXML(url, notifyFlutter: true) { return true }
    return super.application(app, open: url, options: options)
  }

  @discardableResult
  func captureMusicXML(_ url: URL, notifyFlutter: Bool) -> Bool {
    guard url.isFileURL else { return false }
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed { url.stopAccessingSecurityScopedResource() }
    }
    do {
      let fileManager = FileManager.default
      let directory = fileManager.temporaryDirectory
        .appendingPathComponent("incoming-musicxml", isDirectory: true)
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let importDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try fileManager.createDirectory(at: importDirectory, withIntermediateDirectories: true)
      let destination = importDirectory.appendingPathComponent(url.lastPathComponent)
      try fileManager.copyItem(at: url, to: destination)
      pendingFilePath = destination.path
      if notifyFlutter, let channel = incomingFileChannel {
        channel.invokeMethod("fileOpened", arguments: destination.path)
        pendingFilePath = nil
      }
      return true
    } catch {
      return false
    }
  }
}
