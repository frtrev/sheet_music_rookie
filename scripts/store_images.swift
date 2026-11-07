import AppKit
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func image(_ path: String) throws -> CGImage {
    let data = try Data(contentsOf: root.appendingPathComponent(path))
    guard let src = CGImageSourceCreateWithData(data as CFData, nil), let im = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("Invalid image: \(path)") }
    return im
}
func canvas(_ width: Int, _ height: Int, alpha: Bool = false) -> CGContext {
    CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:(alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
}
func save(_ c: CGContext, _ path: String) throws {
    let rep = NSBitmapImageRep(cgImage:c.makeImage()!)
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
    try rep.representation(using:.png,properties:[:])!.write(to:url)
}
let args = CommandLine.arguments
if args.count == 4 && args[1] == "normalize" {
    let config = try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("scripts/store_targets.json"))) as! [String:Any]
    let group = (config["groups"] as! [String:[String:Any]])[args[2]]!
    let size = group["size"] as! [Int]
    for name in config["screens"] as! [String] {
        let source = try image("\(args[3])/\(name).png")
        precondition(source.width == size[0] && source.height == size[1], "Native capture dimensions do not match \(args[2]): \(source.width)x\(source.height)")
        let c = canvas(size[0],size[1]); c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x:0,y:0,width:size[0],height:size[1]))
        c.draw(source,in:CGRect(x:0,y:0,width:size[0],height:size[1]))
        try save(c,"store_assets/\(group["path"]!)/\(name).png")
    }
} else {
    let icon = try image("assets/app_icon/master.png")
    let c = canvas(512,512,alpha:true); c.interpolationQuality = .high
    c.draw(icon,in:CGRect(x:0,y:0,width:512,height:512)); try save(c,"store_assets/android/icon/google_play_icon.png")
    let f = canvas(1024,500)
    let gradient = CGGradient(colorsSpace:space,colors:[NSColor(calibratedRed:0.02,green:0.07,blue:0.22,alpha:1).cgColor,NSColor(calibratedRed:0,green:0.37,blue:0.91,alpha:1).cgColor] as CFArray,locations:[0,1])!
    f.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),end:CGPoint(x:1024,y:500),options:[])
    f.setStrokeColor(NSColor(calibratedRed:0.15,green:0.83,blue:0.95,alpha:0.25).cgColor); f.setLineWidth(2)
    for i in 0..<5 {f.move(to:CGPoint(x:40,y:85+i*18));f.addLine(to:CGPoint(x:984,y:85+i*18));f.strokePath()}
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:f,flipped:false)
    ("Sheet Music\nRookie" as NSString).draw(in:NSRect(x:76,y:214,width:600,height:165),withAttributes:[.font:NSFont.systemFont(ofSize:58,weight:.bold),.foregroundColor:NSColor.white])
    ("Sing it. See it. Shape it." as NSString).draw(at:NSPoint(x:80,y:177),withAttributes:[.font:NSFont.systemFont(ofSize:25,weight:.medium),.foregroundColor:NSColor(calibratedRed:0.6,green:0.95,blue:1,alpha:1)])
    NSGraphicsContext.restoreGraphicsState()
    f.interpolationQuality = .high; f.draw(icon,in:CGRect(x:693,y:147,width:240,height:240))
    try save(f,"store_assets/android/feature_graphic/feature_graphic.png")
    let adaptive = canvas(432,432,alpha:true); adaptive.interpolationQuality = .high
    adaptive.draw(icon,in:CGRect(x:116,y:116,width:200,height:200))
    try save(adaptive,"android/app/src/main/res/drawable/ic_launcher_foreground.png")
}
