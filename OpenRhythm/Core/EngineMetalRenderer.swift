import Metal
import UIKit

/// GPU triangles share edges and alpha blending, avoiding the clipping seams
/// and repeated full-image rasterization of the Core Graphics fallback.
@MainActor
final class EngineMetalRenderer {
  struct Vertex {
    let position: SIMD2<Float>
    let uv: SIMD2<Float>
    let alpha: Float
  }

  let device: MTLDevice
  let queue: MTLCommandQueue
  let layer = CAMetalLayer()
  private let pipeline: MTLRenderPipelineState
  private let linear: MTLSamplerState
  private let nearest: MTLSamplerState
  private let inFlight = DispatchSemaphore(value: 3)
  private var textures = [ObjectIdentifier: (UIImage, MTLTexture)]()

  init(device: MTLDevice) throws {
    self.device = device
    guard let queue = device.makeCommandQueue() else {
      throw EngineInterpreterError.invalidArguments("Metal command queue")
    }
    self.queue = queue
    let library = try device.makeLibrary(source: Self.shader, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "spriteVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "spriteFragment")
    let color = descriptor.colorAttachments[0]!
    color.pixelFormat = .bgra8Unorm
    color.isBlendingEnabled = true
    color.sourceRGBBlendFactor = .one
    color.sourceAlphaBlendFactor = .one
    color.destinationRGBBlendFactor = .oneMinusSourceAlpha
    color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    let sampler = MTLSamplerDescriptor()
    sampler.sAddressMode = .clampToEdge
    sampler.tAddressMode = .clampToEdge
    sampler.minFilter = .linear
    sampler.magFilter = .linear
    guard let linear = device.makeSamplerState(descriptor: sampler) else {
      throw EngineInterpreterError.invalidArguments("Metal linear sampler")
    }
    self.linear = linear
    sampler.minFilter = .nearest
    sampler.magFilter = .nearest
    guard let nearest = device.makeSamplerState(descriptor: sampler) else {
      throw EngineInterpreterError.invalidArguments("Metal nearest sampler")
    }
    self.nearest = nearest
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    layer.isOpaque = true
    layer.backgroundColor = UIColor.black.cgColor
  }

  func resize(to size: CGSize, scale: CGFloat) {
    layer.frame = CGRect(origin: .zero, size: size)
    layer.contentsScale = scale
    let pixels = CGSize(width: size.width * scale, height: size.height * scale)
    if layer.drawableSize != pixels { layer.drawableSize = pixels }
  }

  func prepare(_ assets: EnginePresentationAssets) throws {
    for image in assets.preparedImages {
      let key = ObjectIdentifier(image)
      if textures[key] == nil, let source = image.cgImage {
        textures[key] = (image, try upload(source))
      }
    }
  }

  func draw(host: CommandEngineRuntimeHost, assets: EnginePresentationAssets,
    size: CGSize
  ) throws {
    guard size.width > 0, size.height > 0,
      inFlight.wait(timeout: .now()) == .success else { return }
    guard let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer()
    else {
      inFlight.signal()
      return
    }
    do {
      try encode(EngineRenderer.sprites(host: host, assets: assets),
        size: size, target: drawable.texture, commandBuffer: buffer)
    } catch {
      inFlight.signal()
      throw error
    }
    let semaphore = inFlight
    buffer.addCompletedHandler { _ in semaphore.signal() }
    buffer.present(drawable)
    buffer.commit()
  }

  func encode(_ sprites: [EngineRenderSprite], size: CGSize,
    target: MTLTexture, commandBuffer: MTLCommandBuffer
  ) throws {
    struct Batch {
      let start: Int
      let count: Int
      let texture: MTLTexture
      let interpolation: Bool
    }
    var vertices = [Vertex]()
    var batches = [Batch]()
    for sprite in sprites {
      let mesh = Self.vertices(for: sprite, size: size)
      guard !mesh.isEmpty else { continue }
      guard vertices.count <= 1_000_000 - mesh.count else {
        throw EngineInterpreterError.operationLimitExceeded
      }
      let key = ObjectIdentifier(sprite.image)
      let texture: MTLTexture
      if let cached = textures[key] {
        texture = cached.1
      } else {
        guard let image = sprite.image.cgImage else { continue }
        texture = try upload(image)
        textures[key] = (sprite.image, texture)
      }
      batches.append(Batch(start: vertices.count, count: mesh.count,
        texture: texture, interpolation: sprite.interpolation))
      vertices.append(contentsOf: mesh)
    }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
    else { throw EngineInterpreterError.invalidArguments("Metal render pass") }
    defer { encoder.endEncoding() }
    guard !vertices.isEmpty else { return }
    let vertexBuffer = vertices.withUnsafeBytes {
      device.makeBuffer(bytes: $0.baseAddress!, length: $0.count,
        options: .storageModeShared)
    }
    guard let vertexBuffer else {
      throw EngineInterpreterError.invalidArguments("Metal vertex buffer")
    }
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    for batch in batches {
      encoder.setFragmentTexture(batch.texture, index: 0)
      encoder.setFragmentSamplerState(batch.interpolation ? linear : nearest,
        index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: batch.start,
        vertexCount: batch.count)
    }
  }

  private func upload(_ image: CGImage) throws -> MTLTexture {
    // Normalize extended-range UIKit images as well as atlas crops. Explicit
    // premultiplication matches the pipeline's source-one alpha blending.
    guard let context = CGContext(data: nil, width: image.width,
      height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo:
        CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder32Big.rawValue),
      let bytes = context.data else {
      throw EngineInterpreterError.invalidArguments("Metal sprite pixels")
    }
    context.draw(image, in: CGRect(x: 0, y: 0,
      width: image.width, height: image.height))
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: image.width, height: image.height,
      mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.shaderRead]
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw EngineInterpreterError.invalidArguments("Metal sprite texture")
    }
    texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height),
      mipmapLevel: 0, withBytes: bytes, bytesPerRow: context.bytesPerRow)
    return texture
  }

  static func vertices(for sprite: EngineRenderSprite, size: CGSize) -> [Vertex] {
    guard size.width > 0, size.height > 0, sprite.alpha.isFinite,
      sprite.alpha > 0, sprite.points.count == 4 else { return [] }
    let quad = sprite.points.map {
      EngineGeometry.screenPoint($0, matrix: sprite.matrix, size: size)
    }
    guard quad.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
    let warp = hypot(quad[0].x + quad[2].x - quad[1].x - quad[3].x,
      quad[0].y + quad[2].y - quad[1].y - quad[3].y)
    let divisions = EngineRenderer.tessellationDivisions(warp: warp)
    let points = quad.map { EnginePoint(x: $0.x, y: $0.y) }
    var result = [Vertex]()
    for row in 0..<divisions {
      for column in 0..<divisions {
        let cell = [(column,row), (column,row+1),
          (column+1,row+1), (column+1,row)].map { x, y in
          let u = Double(x) / Double(divisions)
          let v = Double(y) / Double(divisions)
          let point = EngineGeometry.bilinear(points, u: u, v: v)
          return Vertex(position: SIMD2(Float(point.x / size.width * 2 - 1),
            Float(1 - point.y / size.height * 2)),
            uv: SIMD2(Float(u), Float(1 - v)), alpha: Float(min(1, sprite.alpha)))
        }
        for index in [0, 1, 2, 0, 2, 3] { result.append(cell[index]) }
      }
    }
    return result.allSatisfy {
      $0.position.x.isFinite && $0.position.y.isFinite
    } ? result : []
  }

  private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct SpriteVertex { float2 position; float2 uv; float alpha; };
    struct SpriteRaster {
      float4 position [[position]];
      float2 uv;
      float alpha;
    };
    vertex SpriteRaster spriteVertex(
      const device SpriteVertex *vertices [[buffer(0)]], uint id [[vertex_id]]) {
      SpriteVertex v = vertices[id];
      return {float4(v.position, 0, 1), v.uv, v.alpha};
    }
    fragment float4 spriteFragment(SpriteRaster in [[stage_in]],
      texture2d<float> image [[texture(0)]], sampler filtering [[sampler(0)]]) {
      return image.sample(filtering, in.uv) * in.alpha;
    }
    """
}
