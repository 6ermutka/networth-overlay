// Рисует иконку приложения: золотая монета со стрелкой роста на тёмной плитке.
// Запуск: swift make-icon.swift <папка>  → <папка>/AppIcon.png (1024×1024)
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

// Плитка по сетке иконок macOS: 824 pt с полями по 100.
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
NSGradient(colors: [rgb(0x232A3A), rgb(0x0B0E15)])!.draw(in: tile, angle: -90)

rgb(0xFFD36B, 0.28).setStroke()
tile.lineWidth = 6
tile.stroke()

// Монета.
let coin = NSRect(x: 252, y: 252, width: 520, height: 520)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -14)
NSGraphicsContext.saveGraphicsState()
shadow.set()
rgb(0xC98A14).setFill()
NSBezierPath(ovalIn: coin).fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [rgb(0xFFE9A6), rgb(0xF6BE3C), rgb(0xC98A14)])!.draw(in: NSBezierPath(ovalIn: coin), angle: -90)

let ring = NSBezierPath(ovalIn: coin.insetBy(dx: 38, dy: 38))
rgb(0x8A5A08, 0.55).setStroke()
ring.lineWidth = 10
ring.stroke()

// Стрелка роста.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 512, y: 668))
arrow.line(to: NSPoint(x: 650, y: 516))
arrow.line(to: NSPoint(x: 566, y: 516))
arrow.line(to: NSPoint(x: 566, y: 366))
arrow.line(to: NSPoint(x: 458, y: 366))
arrow.line(to: NSPoint(x: 458, y: 516))
arrow.line(to: NSPoint(x: 374, y: 516))
arrow.close()
arrow.lineJoinStyle = .round
rgb(0x4A2F04).setFill()
arrow.fill()

NSGraphicsContext.current = nil
let out = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
