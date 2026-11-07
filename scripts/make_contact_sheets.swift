import AppKit
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let config = try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("scripts/store_targets.json"))) as! [String:Any]
let groups = config["groups"] as! [String:[String:Any]]
let names = config["screens"] as! [String]
let space = CGColorSpace(name:CGColorSpace.sRGB)!
for (key, group) in groups {
    let context = CGContext(data:nil,width:1200,height:1800,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(NSColor(calibratedWhite:0.88,alpha:1).cgColor);context.fill(CGRect(x:0,y:0,width:1200,height:1800))
    for (i,name) in names.enumerated() {
        let url = root.appendingPathComponent("store_assets/\(group["path"]!)/\(name).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),let im=CGImageSourceCreateImageAtIndex(source,0,nil) else {continue}
        let scale = min(380.0/Double(im.width),840.0/Double(im.height))
        let w=Double(im.width)*scale;let h=Double(im.height)*scale
        let x=Double(i%3)*400+(400-w)/2;let y=Double(1-i/3)*900+50
        context.draw(im,in:CGRect(x:x,y:y,width:w,height:h))
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        (name as NSString).draw(at:NSPoint(x:Double(i%3)*400+10,y:Double(1-i/3)*900+20),withAttributes:[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
    }
    let out=root.appendingPathComponent("release/reports/contact-sheets/\(key).png")
    try FileManager.default.createDirectory(at:out.deletingLastPathComponent(),withIntermediateDirectories:true)
    try NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!.write(to:out)
}
