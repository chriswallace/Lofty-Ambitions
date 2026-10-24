import AppKit
let size = NSSize(width:1024,height:1024)
let image = NSImage(size:size)
image.lockFocus()
let rounded = NSBezierPath(roundedRect:NSRect(x:60,y:60,width:904,height:904),xRadius:205,yRadius:205)
NSColor(srgbRed:0.14,green:0.25,blue:0.33,alpha:1).setFill(); rounded.fill()
let ctx = NSGraphicsContext.current!.cgContext
ctx.saveGState(); rounded.addClip()
NSGradient(starting:NSColor(srgbRed:0.57,green:0.75,blue:0.79,alpha:1),ending:NSColor(srgbRed:0.83,green:0.88,blue:0.81,alpha:1))!.draw(in:NSRect(x:60,y:60,width:904,height:904),angle:270)
NSColor(srgbRed:0.97,green:0.89,blue:0.69,alpha:1).setFill(); NSBezierPath(ovalIn:NSRect(x:715,y:735,width:97,height:97)).fill()
for row in 0..<8 {
 let y = 178+CGFloat(row)*77
 NSColor(srgbRed:0.27,green:0.39,blue:0.44,alpha:1).setFill(); NSRect(x:270,y:y,width:484,height:70).fill()
 for col in 0..<6 {
  NSColor(srgbRed:row%3==0 ? 0.90:0.73,green:0.79,blue:row%3==0 ? 0.57:0.75,alpha:1).setFill()
  NSRect(x:283+CGFloat(col)*79,y:y+10,width:66,height:46).fill()
  NSColor(srgbRed:0.49,green:0.59,blue:0.60,alpha:1).setFill(); NSRect(x:314+CGFloat(col)*79,y:y+10,width:3,height:46).fill()
 }
 NSColor(srgbRed:0.86,green:0.86,blue:0.74,alpha:1).setFill(); NSRect(x:255,y:y+68,width:514,height:9).fill()
}
NSColor(srgbRed:0.18,green:0.29,blue:0.36,alpha:1).setFill(); NSRect(x:472,y:178,width:80,height:616).fill()
NSColor(srgbRed:0.9,green:0.77,blue:0.48,alpha:1).setFill(); NSRect(x:485,y:430,width:54,height:60).fill()
NSColor(srgbRed:0.27,green:0.39,blue:0.44,alpha:1).setFill(); NSRect(x:463,y:796,width:98,height:39).fill()
NSColor(srgbRed:0.86,green:0.86,blue:0.74,alpha:1).setFill(); NSRect(x:448,y:833,width:128,height:10).fill()
NSColor(srgbRed:0.27,green:0.39,blue:0.44,alpha:1).setFill(); NSRect(x:236,y:150,width:552,height:28).fill()
ctx.restoreGState(); image.unlockFocus()
let data = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data:data)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
