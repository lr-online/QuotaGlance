#!/usr/bin/env swift

import AppKit
import Foundation

struct HarmonyOSIconRenderer {
  let canvasSize = 1024

  // HarmonyOS applies its own icon mask; keep all foreground artwork inside the
  // centered safe zone (~66% of the canvas, i.e. 676x676 at 1024).
  var foregroundSafeRect: CGRect {
    let side = CGFloat(canvasSize) * 0.66
    let origin = (CGFloat(canvasSize) - side) / 2
    return CGRect(x: origin, y: origin, width: side, height: side)
  }

  func render(appScopeMediaDirectory: URL, entryMediaDirectory: URL) throws {
    try writeBackground(to: appScopeMediaDirectory)
    try writeBackground(to: entryMediaDirectory)
    try writeForeground(to: appScopeMediaDirectory)
    try writeForeground(to: entryMediaDirectory)
    try writeStartIcon(to: entryMediaDirectory)
  }

  // Full-bleed dark navy gradient (no rounded corners — the system applies the mask).
  private func writeBackground(to directory: URL) throws {
    try withBitmapContext(size: canvasSize) { context, rect in
      context.clear(rect)
      let gradient = NSGradient(
        colors: [
          NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.24, alpha: 1.0),
          NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1.0)
        ]
      )!
      gradient.draw(in: rect, angle: 270)
    }.write(to: directory.appendingPathComponent("background.png"))
  }

  // Transparent foreground layer: glyph composed within the safe zone.
  private func writeForeground(to directory: URL) throws {
    try withBitmapContext(size: canvasSize) { context, rect in
      context.clear(rect)
      let safe = foregroundSafeRect
      drawRing(in: safe)
      drawChart(in: safe)
      drawAccent(in: safe)
    }.write(to: directory.appendingPathComponent("foreground.png"))
  }

  // Fully composed icon: navy gradient rounded-rect (23% radius) with the glyph,
  // on transparent. Used as the start-window icon.
  private func writeStartIcon(to directory: URL) throws {
    try withBitmapContext(size: canvasSize) { context, rect in
      context.clear(rect)
      drawBackground(in: rect)
      drawRing(in: rect)
      drawChart(in: rect)
      drawAccent(in: rect)
    }.write(to: directory.appendingPathComponent("startIcon.png"))
  }

  private func withBitmapContext(
    size: Int,
    draw: (CGContext, CGRect) -> Void
  ) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: size,
      pixelsHigh: size,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      throw NSError(domain: "QuotaGlanceIcon", code: 1, userInfo: nil)
    }

    bitmap.size = NSSize(width: size, height: size)

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
      throw NSError(domain: "QuotaGlanceIcon", code: 2, userInfo: nil)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = graphicsContext.cgContext
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    draw(context, rect)
    graphicsContext.flushGraphics()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw NSError(domain: "QuotaGlanceIcon", code: 3, userInfo: nil)
    }
    return png
  }

  private func drawBackground(in rect: CGRect) {
    let inset = rect.width * 0.015
    let backgroundRect = rect.insetBy(dx: inset, dy: inset)
    let radius = rect.width * 0.23

    let gradient = NSGradient(
      colors: [
        NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.24, alpha: 1.0),
        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1.0)
      ]
    )!
    let shape = NSBezierPath(
      roundedRect: backgroundRect,
      xRadius: radius,
      yRadius: radius
    )
    shape.addClip()
    gradient.draw(
      in: shape,
      angle: 270
    )

    NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
    shape.lineWidth = max(1, rect.width * 0.02)
    shape.stroke()

    let sheenRect = CGRect(
      x: backgroundRect.minX,
      y: backgroundRect.midY,
      width: backgroundRect.width,
      height: backgroundRect.height * 0.55
    )
    let sheen = NSGradient(
      colors: [
        NSColor(calibratedRed: 0.38, green: 0.69, blue: 0.96, alpha: 0.18),
        NSColor.clear
      ]
    )!
    sheen.draw(in: sheenRect, angle: 90)
  }

  private func drawRing(in rect: CGRect) {
    let ringRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
    let track = NSBezierPath(ovalIn: ringRect)
    track.lineWidth = rect.width * 0.10
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    track.stroke()

    let progress = NSBezierPath()
    progress.appendArc(
      withCenter: CGPoint(x: rect.midX, y: rect.midY),
      radius: ringRect.width / 2,
      startAngle: 140,
      endAngle: 390,
      clockwise: false
    )
    progress.lineWidth = track.lineWidth
    progress.lineCapStyle = .round
    NSColor(calibratedRed: 0.34, green: 0.88, blue: 0.84, alpha: 1.0).setStroke()
    progress.stroke()
  }

  private func drawChart(in rect: CGRect) {
    let points = [
      CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.36),
      CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.47),
      CGPoint(x: rect.minX + rect.width * 0.52, y: rect.minY + rect.height * 0.44),
      CGPoint(x: rect.minX + rect.width * 0.64, y: rect.minY + rect.height * 0.60),
      CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.54)
    ]

    let line = NSBezierPath()
    line.move(to: points[0])
    for point in points.dropFirst() {
      line.line(to: point)
    }
    line.lineWidth = max(1.5, rect.width * 0.045)
    line.lineJoinStyle = .round
    line.lineCapStyle = .round
    NSColor(calibratedWhite: 1.0, alpha: 0.94).setStroke()
    line.stroke()

    for point in points {
      let diameter = max(2.5, rect.width * 0.075)
      let markerRect = CGRect(
        x: point.x - diameter / 2,
        y: point.y - diameter / 2,
        width: diameter,
        height: diameter
      )
      NSColor(calibratedRed: 0.53, green: 0.92, blue: 0.96, alpha: 1.0).setFill()
      NSBezierPath(ovalIn: markerRect).fill()
    }
  }

  private func drawAccent(in rect: CGRect) {
    let accentRect = CGRect(
      x: rect.minX + rect.width * 0.23,
      y: rect.minY + rect.height * 0.20,
      width: rect.width * 0.54,
      height: rect.height * 0.07
    )
    let accent = NSBezierPath(
      roundedRect: accentRect,
      xRadius: accentRect.height / 2,
      yRadius: accentRect.height / 2
    )
    NSColor(calibratedRed: 0.33, green: 0.39, blue: 0.53, alpha: 0.65).setFill()
    accent.fill()
  }
}

let scriptURL = URL(fileURLWithPath: #filePath)
let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let appScopeMediaDirectory = repositoryRoot
  .appendingPathComponent("HarmonyOS/AppScope/resources/base/media", isDirectory: true)
let entryMediaDirectory = repositoryRoot
  .appendingPathComponent("HarmonyOS/entry/src/main/resources/base/media", isDirectory: true)

try HarmonyOSIconRenderer().render(
  appScopeMediaDirectory: appScopeMediaDirectory,
  entryMediaDirectory: entryMediaDirectory
)
print("HarmonyOS icons written to:")
print("  \(appScopeMediaDirectory.path)")
print("  \(entryMediaDirectory.path)")
