import AppKit
let out = CommandLine.arguments[1]
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 206, yRadius: 206)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor(calibratedWhite: 0.05, alpha: 0.28); shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
NSColor(calibratedRed: 0.04, green: 0.27, blue: 0.75, alpha: 1).setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [NSColor(calibratedRed: 0.04, green: 0.15, blue: 0.59, alpha: 1), NSColor(calibratedRed: 0.035, green: 0.40, blue: 0.94, alpha: 1), NSColor(calibratedRed: 0.04, green: 0.80, blue: 0.89, alpha: 1)])!.draw(in: tile, angle: 60)
NSGraphicsContext.saveGraphicsState(); tile.addClip()
let sweep=NSBezierPath(); sweep.move(to:NSPoint(x:70,y:240)); sweep.curve(to:NSPoint(x:950,y:870),controlPoint1:NSPoint(x:490,y:210),controlPoint2:NSPoint(x:650,y:850)); sweep.line(to:NSPoint(x:1050,y:1100)); sweep.line(to:NSPoint(x:-50,y:1100)); sweep.close();NSColor.white.withAlphaComponent(0.07).setFill();sweep.fill()
NSGraphicsContext.restoreGraphicsState()
let rim=NSBezierPath(roundedRect:NSRect(x:66,y:66,width:892,height:892),xRadius:204,yRadius:204);rim.lineWidth=3;NSColor.white.withAlphaComponent(0.20).setStroke();rim.stroke()
// A single forward-swept download mark: readable at small Dock sizes.
let arrow=NSBezierPath();arrow.move(to:NSPoint(x:567,y:783));arrow.line(to:NSPoint(x:726,y:783));arrow.line(to:NSPoint(x:591,y:473));arrow.line(to:NSPoint(x:757,y:473));arrow.line(to:NSPoint(x:438,y:223));arrow.line(to:NSPoint(x:332,y:473));arrow.line(to:NSPoint(x:482,y:473));arrow.close()
NSGraphicsContext.saveGraphicsState();let s=NSShadow();s.shadowColor=NSColor(calibratedRed:0,green:0.10,blue:0.34,alpha:0.25);s.shadowBlurRadius=18;s.shadowOffset=NSSize(width:0,height:-9);s.set();NSColor.white.setFill();arrow.fill();NSGraphicsContext.restoreGraphicsState()
func streak(_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ alpha:CGFloat){let p=NSBezierPath();p.move(to:NSPoint(x:x,y:y));p.line(to:NSPoint(x:x+width,y:y));p.lineWidth=29;p.lineCapStyle = .round;NSColor(calibratedRed:0.64,green:0.97,blue:1,alpha:alpha).setStroke();p.stroke()}
streak(257,715,220,0.95);streak(215,625,214,0.78);streak(250,535,122,0.55)
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:out))
