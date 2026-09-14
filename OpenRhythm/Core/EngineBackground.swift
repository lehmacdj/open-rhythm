import UIKit
import CoreImage
import ImageIO
import SwiftUI

struct EngineBackgroundData: Decodable {
  let aspectRatio: Double?
  let fit: String
  let color: String
  let scaleX: Double?
  let scaleY: Double?

  func quad(imageAspect: Double, screenAspect: Double) throws -> [Double] {
    let aspect = aspectRatio ?? imageAspect
    let xScale = scaleX ?? 1
    let yScale = scaleY ?? 1
    guard aspect.isFinite, aspect > 0, screenAspect.isFinite, screenAspect > 0,
      xScale.isFinite, yScale.isFinite else {
      throw EngineInterpreterError.invalidArguments("background dimensions")
    }
    let height: Double
    switch fit {
    case "width": height = screenAspect / aspect
    case "height": height = 1
    case "contain": height = min(1, screenAspect / aspect)
    case "cover": height = max(1, screenAspect / aspect)
    default: throw EngineInterpreterError.invalidArguments("background fit: \(fit)")
    }
    let x = height * aspect * xScale
    let y = height * yScale
    guard x.isFinite, y.isFinite else {
      throw EngineInterpreterError.invalidArguments("background scale")
    }
    return [-x, -y, -x, y, x, y, x, -y]
  }
}

struct EngineBackgroundConfiguration: Decodable {
  let blur: Double
  let mask: String
}

struct EngineHTMLColor: Equatable {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init(_ text: String, allowsAlpha: Bool) throws {
    let digits = String(text.dropFirst())
    let sizes = allowsAlpha ? [3, 4, 6, 8] : [3, 6]
    guard text.first == "#", sizes.contains(digits.count),
      digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
      let value = UInt32(digits, radix: 16) else {
      throw EngineInterpreterError.invalidArguments("background HTML color")
    }
    let short = digits.count <= 4
    let hasAlpha = digits.count == 4 || digits.count == 8
    let bits = short ? 4 : 8
    let mask: UInt32 = short ? 15 : 255
    func channel(_ index: Int) -> Double {
      Double((value >> (bits * index)) & mask) / Double(mask)
    }
    alpha = hasAlpha ? channel(0) : 1
    blue = channel(hasAlpha ? 1 : 0)
    green = channel(hasAlpha ? 2 : 1)
    red = channel(hasAlpha ? 3 : 2)
  }

  var uiColor: UIColor {
    UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}

@MainActor
final class EngineBackgroundAssets {
  let data: EngineBackgroundData
  let image: CGImage
  let imageAspect: Double
  let color: UIColor
  let mask: UIColor

  init(presentation: RuntimePresentation) throws {
    data = try CompressedJSONDecoder.decode(EngineBackgroundData.self,
      from: presentation.data("backgroundData"))
    let configuration = try CompressedJSONDecoder.decode(
      EngineBackgroundConfiguration.self,
      from: presentation.data("backgroundConfiguration"))
    color = try EngineHTMLColor(data.color, allowsAlpha: false).uiColor
    mask = try EngineHTMLColor(configuration.mask, allowsAlpha: true).uiColor
    let encoded = try presentation.data("backgroundImage")
    guard configuration.blur.isFinite, (0...1).contains(configuration.blur),
      encoded.count <= 32 * 1024 * 1024,
      let container = CGImageSourceCreateWithData(encoded as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(container, 0, nil)
        as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 32768, height <= 32768,
      width * height <= 128_000_000,
      let source = CGImageSourceCreateThumbnailAtIndex(container, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 2048,
        kCGImageSourceShouldCacheImmediately: true
      ] as CFDictionary) else {
      throw EngineInterpreterError.invalidArguments("background image or blur")
    }
    // Preserve the original aspect even when thumbnail dimensions round.
    // Decoding/blur is bounded to 2048 per side, at most 16 MiB per RGBA8 image.
    imageAspect = Double(width) / Double(height)
    _ = try data.quad(imageAspect: imageAspect, screenAspect: 1)
    // Normalize blur to image size once at preparation. The protocol specifies
    // a 0...1 amount, but not a pixel radius; the 5% radius is host policy.
    if configuration.blur > 0 {
      let input = CIImage(cgImage: source)
      let radius = configuration.blur * Double(min(source.width, source.height)) * 0.05
      let output = input.clampedToExtent().applyingFilter("CIGaussianBlur",
        parameters: [kCIInputRadiusKey: radius]).cropped(to: input.extent)
      guard let blurred = CIContext().createCGImage(output, from: input.extent) else {
        throw EngineInterpreterError.invalidArguments("background blur")
      }
      image = blurred
    } else {
      image = source
    }
  }

  func initialQuad(screenAspect: Double) throws -> [Double] {
    try data.quad(imageAspect: imageAspect, screenAspect: screenAspect)
  }
}

/// Unit-square-to-quad homography. Unlike skin sprites, backgrounds require
/// perspective interpolation. Core Animation applies the homogeneous divide.
enum EngineBackgroundProjection {
  static func transform(quad: [Double], size: CGSize) -> CATransform3D? {
    guard quad.count == 8, quad.allSatisfy(\.isFinite),
      size.width.isFinite, size.height.isFinite,
      size.width > 0, size.height > 0 else { return nil }
    func point(_ index: Int) -> CGPoint {
      CGPoint(x: size.width / 2 + quad[index * 2] * size.height / 2,
        y: size.height / 2 - quad[index * 2 + 1] * size.height / 2)
    }
    let p0 = point(1), p1 = point(2), p2 = point(3), p3 = point(0)
    let dx1 = p1.x - p2.x, dx2 = p3.x - p2.x
    let dy1 = p1.y - p2.y, dy2 = p3.y - p2.y
    let dx3 = p0.x - p1.x + p2.x - p3.x
    let dy3 = p0.y - p1.y + p2.y - p3.y
    let determinant = dx1 * dy2 - dx2 * dy1
    guard determinant.isFinite, abs(determinant) > 1e-10 else { return nil }
    let g = (dx3 * dy2 - dx2 * dy3) / determinant
    let h = (dx1 * dy3 - dx3 * dy1) / determinant
    // Reject folded/degenerate quads and poles through the image. Mirroring
    // both or either dimension remains valid when the homogeneous W stays >0.
    guard [1 + g, 1 + h, 1 + g + h].allSatisfy({ $0.isFinite && $0 > 1e-8 })
    else { return nil }
    var result = CATransform3DIdentity
    result.m11 = p1.x - p0.x + g * p1.x
    result.m21 = p3.x - p0.x + h * p3.x
    result.m41 = p0.x
    result.m12 = p1.y - p0.y + g * p1.y
    result.m22 = p3.y - p0.y + h * p3.y
    result.m42 = p0.y
    result.m14 = g
    result.m24 = h
    guard [result.m11, result.m21, result.m41, result.m12,
      result.m22, result.m42].allSatisfy(\.isFinite) else { return nil }
    return result
  }
}

@MainActor
final class EngineBackgroundLayer {
  let layer = CALayer()
  private let picture = CALayer()
  private let maskLayer = CALayer()

  init() {
    layer.masksToBounds = true
    picture.anchorPoint = .zero
    picture.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    picture.position = .zero
    picture.isDoubleSided = true
    layer.addSublayer(picture)
    layer.addSublayer(maskLayer)
  }

  func prepare(_ assets: EngineBackgroundAssets?) {
    layer.backgroundColor = (assets?.color ?? .black).cgColor
    picture.contents = assets?.image
    maskLayer.backgroundColor = (assets?.mask ?? .clear).cgColor
  }

  func update(quad: [Double], size: CGSize) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.frame = CGRect(origin: .zero, size: size)
    maskLayer.frame = layer.bounds
    if let transform = EngineBackgroundProjection.transform(quad: quad, size: size) {
      picture.transform = transform
      picture.isHidden = false
    } else {
      picture.isHidden = true
    }
    CATransaction.commit()
  }
}

#if DEBUG
private struct BackgroundProjectionPreview: UIViewRepresentable {
  func makeUIView(context: Context) -> Surface { Surface() }
  func updateUIView(_ view: Surface, context: Context) {}

  final class Surface: UIView {
    private let background = EngineBackgroundLayer()

    override init(frame: CGRect) {
      super.init(frame: frame)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256),
        format: format).image { context in
        for y in 0..<8 {
          for x in 0..<8 {
            (y < 4 ? UIColor.cyan : .orange).withAlphaComponent(
              (x + y).isMultiple(of: 2) ? 1 : 0.4).setFill()
            context.fill(CGRect(x: x * 32, y: y * 32, width: 32, height: 32))
          }
        }
      }
      let assets = try! EngineBackgroundAssets(presentation: RuntimePresentation(resources: [
        "backgroundData": Data(##"{"fit":"cover","color":"#234"}"##.utf8),
        "backgroundConfiguration": Data(##"{"blur":0,"mask":"#0002"}"##.utf8),
        "backgroundImage": image.pngData()!
      ]))
      background.prepare(assets)
      layer.addSublayer(background.layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
      super.layoutSubviews()
      background.update(quad: [-1.5, -0.9, -0.75, 0.9, 0.75, 0.9, 1.5, -0.9],
        size: bounds.size)
    }
  }
}

#Preview("Background Perspective", traits: .fixedLayout(width: 600, height: 360)) {
  BackgroundProjectionPreview()
}
#endif
