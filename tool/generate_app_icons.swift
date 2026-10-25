// Run from the repository root: swift tool/generate_app_icons.swift
import AppKit
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = NSImage(contentsOf: root.appendingPathComponent("assets/app_icon/master.png"))!
func export(_ path: String, _ size: Int, alpha: Bool = false) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    context.interpolationQuality = .high
    var rect = CGRect(origin: .zero, size: source.size)
    let cgImage = source.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
    let result = NSBitmapImageRep(data: try Data(contentsOf: url))!
    precondition(result.pixelsWide == size && result.pixelsHigh == size)
    precondition(result.hasAlpha == alpha)
    print("Verified \(path): \(size)×\(size), alpha=\(alpha)")
}
let catalog = "ios/Runner/Assets.xcassets/AppIcon.appiconset/"
let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(catalog + "Contents.json"))) as! [String: Any]
for entry in json["images"] as! [[String: String]] {
    let points = Double(entry["size"]!.components(separatedBy: "x")[0])!
    let scale = Double(entry["scale"]!.dropLast())!
    try export(catalog + entry["filename"]!, Int(points * scale))
}
for (density, size) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {
    try export("android/app/src/main/res/mipmap-\(density)/ic_launcher.png", size)
}
try export("assets/app_icon/app-store-1024.png", 1024)
try export("assets/app_icon/google-play-512.png", 512, alpha: true)
