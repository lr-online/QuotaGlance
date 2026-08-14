#!/usr/bin/env swift

import AppKit
import Foundation

struct IconRenderer {
  let outputDirectory: URL
  let sizes = [16, 32, 64, 128, 256, 512, 1024]

  func render() throws {
    try createDirectories()
    try writeCatalogContents()
    for size in sizes {
      try writeIcon(size: size)
    }
  }

  private func createDirectories() throws {
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true,
      attributes: nil
    )
  }

  private func writeCatalogContents() throws {
    let assetCatalogDirectory = outputDirectory.deletingLastPathComponent()
    let assetCatalogContents = """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    let appIconContents = """
    {
      "images" : [
        {
          "filename" : "icon-16.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "16x16"
        },
        {
          "filename" : "icon-32.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "16x16"
        },
        {
          "filename" : "icon-32.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "32x32"
        },
        {
          "filename" : "icon-64.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "32x32"
        },
        {
          "filename" : "icon-128.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "128x128"
        },
        {
          "filename" : "icon-256.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "128x128"
        },
        {
          "filename" : "icon-256.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "256x256"
        },
        {
          "filename" : "icon-512.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "256x256"
        },
        {
          "filename" : "icon-512.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "512x512"
        },
        {
          "filename" : "icon-1024.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "512x512"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """

    try assetCatalogContents.write(
      to: assetCatalogDirectory.appendingPathComponent("Contents.json"),
      atomically: true,
      encoding: .utf8
    )
    try appIconContents.write(
      to: outputDirectory.appendingPathComponent("Contents.json"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func writeIcon(size: Int) throws {
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
    context.clear(rect)
    drawBackground(in: rect)
    drawRing(in: rect)
    drawChart(in: rect)
    drawAccent(in: rect)
    graphicsContext.flushGraphics()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw NSError(domain: "QuotaGlanceIcon", code: 3, userInfo: nil)
    }

    try png.write(to: outputDirectory.appendingPathComponent("icon-\(size).png"))
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
let iconSetDirectory = repositoryRoot
  .appendingPathComponent("Platforms/macOS/App/Assets.xcassets", isDirectory: true)
  .appendingPathComponent("AppIcon.appiconset", isDirectory: true)

try IconRenderer(outputDirectory: iconSetDirectory).render()
