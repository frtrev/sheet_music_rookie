import AppKit
import Foundation
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let source=CGImageSourceCreateWithURL(root.appendingPathComponent("assets/app_icon/app-store-1024.png") as CFURL,nil)!
let icon=CGImageSourceCreateImageAtIndex(source,0,nil)!
let space=CGColorSpace(name:CGColorSpace.sRGB)!
for scale in 1...3 {
    let size=168*scale
    let context=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(icon,in:CGRect(x:0,y:0,width:size,height:size))
    let name=scale==1 ? "LaunchImage.png" : "LaunchImage@\(scale)x.png"
    let file=root.appendingPathComponent("ios/Runner/Assets.xcassets/LaunchImage.imageset/\(name)")
    try NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!.write(to:file)
    print("Verified launch artwork: \(name) \(size)x\(size)")
}
