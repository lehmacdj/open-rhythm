import Metal
import Observation
import SwiftUI
import UIKit

/// A rendered preview, ready to scroll: sprites projected into canvas
/// coordinates once, then translated and culled for each scroll position.
@MainActor
final class EnginePreviewScene {
  private struct Item {
    let sprite: EngineRenderSprite
    let bounds: CGRect
  }

  let canvas: EnginePreviewCanvas
  let prints: [EnginePrintCommand]
  let menu: EnginePreviewUIElement
  let progress: EnginePreviewUIElement
  private let items: [Item]
  private static let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0,
    0, 0, 1, 0, 0, 0, 0, 1]

  var spriteCount: Int { items.count }
  /// Each sprite's extent in canvas coordinates.
  var spriteBounds: [CGRect] { items.map(\.bounds) }

  init(frame: EnginePreviewFrame, assets: EnginePresentationAssets) {
    canvas = frame.canvas
    prints = frame.prints
    menu = frame.menu
    progress = frame.progress
    // The skin transform is fixed after preprocessing, so applying it here
    // matches the renderers' per-point projection exactly.
    items = EngineRenderer.sprites(draws: frame.draws, assets: assets)
      .compactMap { sprite in
        guard sprite.matrix.count == 16 else { return nil }
        let m = sprite.matrix
        let points = sprite.points.map { p -> EnginePoint in
          let w = m[12] * p.x + m[13] * p.y + m[15]
          return EnginePoint(x: (m[0] * p.x + m[1] * p.y + m[3]) / w,
            y: (m[4] * p.x + m[5] * p.y + m[7]) / w)
        }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
          return nil
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        let projected = EngineRenderSprite(image: sprite.image,
          points: points, matrix: Self.identity, alpha: sprite.alpha,
          interpolation: sprite.interpolation,
          textureRegion: sprite.textureRegion, renderMode: sprite.renderMode)
        return Item(sprite: projected, bounds: CGRect(x: xs.min()!,
          y: ys.min()!, width: xs.max()! - xs.min()!,
          height: ys.max()! - ys.min()!))
      }
  }

  /// Sprites on screen at `position`, in drawing order.
  func sprites(at position: Double) -> [EngineRenderSprite] {
    let visible = canvas.visibleBounds(at: position).insetBy(dx: -0.01,
      dy: -0.01)
    let offset = canvas.offset(at: position)
    let matrix: [Double] = [1, 0, 0, offset.x, 0, 1, 0, offset.y,
      0, 0, 1, 0, 0, 0, 0, 1]
    return items.compactMap { item in
      guard item.bounds.intersects(visible) else { return nil }
      let sprite = item.sprite
      return EngineRenderSprite(image: sprite.image, points: sprite.points,
        matrix: matrix, alpha: sprite.alpha,
        interpolation: sprite.interpolation,
        textureRegion: sprite.textureRegion, renderMode: sprite.renderMode)
    }
  }

  /// Prints whose box may reach the screen at `position`.
  func prints(at position: Double) -> [EnginePrintCommand] {
    let visible = canvas.visibleBounds(at: position)
    return prints.filter {
      let reach = abs($0.size.x) + abs($0.size.y)
      return CGRect(x: $0.anchor.x - reach, y: $0.anchor.y - reach,
        width: 2 * reach, height: 2 * reach).intersects(visible)
    }
  }
}

@MainActor
@Observable
final class ChartPreviewModel {
  enum Phase: Equatable {
    case loading, ready, failed(String)
  }

  private struct Layout: Equatable {
    let aspectRatio: Double
    let safeArea: [Double]
  }

  private(set) var phase = Phase.loading
  private(set) var scene: EnginePreviewScene?
  /// Fraction of the scroll range, 0 at the chart's start.
  var progress = 0.0
  @ObservationIgnored var scrollToProgress: ((Double) -> Void)?
  @ObservationIgnored private var bundle: PreviewBundle?
  @ObservationIgnored private var assets: EnginePresentationAssets?
  @ObservationIgnored private var options = [Double]()
  @ObservationIgnored private var layout: Layout?
  @ObservationIgnored private var renderTask: Task<Void, Never>?
  @ObservationIgnored private let loader: RuntimeBundleLoader

  init(loader: RuntimeBundleLoader = RuntimeBundleLoader()) {
    self.loader = loader
  }

  func load(level: SonolusLevelItem, server: ServerDescriptor) async {
    guard bundle == nil else { return }
    do {
      let bundle = try await loader.loadPreview(level: level, from: server)
      try Task.checkCancellation()
      let assets = try EnginePresentationAssets(
        skinDefinition: bundle.engine.skin,
        particleDefinition: EngineParticleDefinition(effects: []),
        presentation: bundle.presentation)
      // Preview options are the level options the player saved for play,
      // including engine options that only affect previews.
      let settings = UserPreferences.shared.gameplay(
        for: level.engineKey(server: server))
      assets.configureRenderMode(preferred: settings.skinRenderMode)
      options = assets.configuration.runtimeOptions(preferences: settings)
      self.assets = assets
      self.bundle = bundle
      if let layout { render(layout) }
    } catch is CancellationError {
      return
    } catch {
      phase = .failed(Self.describe(error))
    }
  }

  /// Renders for this screen shape; the engine lays out by aspect ratio.
  func layout(size: CGSize, safeAreaInsets: EdgeInsets) {
    guard size.width > 0, size.height > 0 else { return }
    let aspect = Double(size.width / size.height)
    let unit = Double(size.height) / 2
    let next = Layout(aspectRatio: aspect, safeArea: [
      -aspect + Double(safeAreaInsets.leading) / unit,
      aspect - Double(safeAreaInsets.trailing) / unit,
      -1 + Double(safeAreaInsets.bottom) / unit,
      1 - Double(safeAreaInsets.top) / unit])
    guard next != layout else { return }
    layout = next
    if bundle != nil { render(next) }
  }

  func seek(toProgress value: Double) {
    progress = min(1, max(0, value))
    scrollToProgress?(progress)
  }

  private func render(_ layout: Layout) {
    guard let bundle, let assets else { return }
    renderTask?.cancel()
    let options = options
    let sprites = Set(assets.skin.keys)
    renderTask = Task {
      do {
        // The whole chart is interpreted at once; keep it off the main actor.
        let frame = try await Task.detached(priority: .userInitiated) {
          try EnginePreviewRuntime(engine: bundle.engine, level: bundle.level,
            options: options, aspectRatio: layout.aspectRatio,
            skinSpriteIDs: sprites, rom: bundle.engineROM,
            safeArea: layout.safeArea).render()
        }.value
        guard !Task.isCancelled, self.layout == layout else { return }
        scene = EnginePreviewScene(frame: frame, assets: assets)
        phase = .ready
      } catch {
        guard !Task.isCancelled else { return }
        phase = .failed(Self.describe(error))
      }
    }
  }

  private static func describe(_ error: Error) -> String {
    if let error = error as? LocalizedError, error.errorDescription != nil {
      return error.localizedDescription
    }
    let value = error as NSError
    return "\(value.localizedDescription) (\(value.domain), \(value.code))"
  }
}

/// A scrollable view of one chart, drawn by its engine's preview data.
struct ChartPreviewView: View {
  let song: CatalogSong
  let level: SonolusLevelItem
  @State private var model = ChartPreviewModel()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    // The outer reader keeps the safe area so its insets are real; the
    // preview itself fills the whole screen.
    GeometryReader { outer in
      GeometryReader { geometry in
        ZStack {
          Color.black
          switch model.phase {
          case .loading:
            ProgressView("Preparing preview…")
              .tint(.white)
          case .failed(let message):
            ContentUnavailableView("Couldn’t Preview",
              systemImage: "exclamationmark.triangle",
              description: Text(message))
          case .ready:
            if let scene = model.scene {
              ChartPreviewCanvas(scene: scene, model: model)
              controls(scene: scene, size: geometry.size)
            }
          }
          if model.scene == nil {
            closeButton
              .frame(maxWidth: .infinity, maxHeight: .infinity,
                alignment: .topTrailing)
              .padding(.top, outer.safeAreaInsets.top + 8)
              .padding(.trailing, outer.safeAreaInsets.trailing + 12)
          }
        }
        .foregroundStyle(.white)
        .onChange(of: geometry.size, initial: true) { _, size in
          model.layout(size: size, safeAreaInsets: outer.safeAreaInsets)
        }
      }
      .ignoresSafeArea()
    }
    .toolbar(.hidden, for: .navigationBar)
    .statusBarHidden()
    .navigationTitle(song.title.displayValue())
    .task {
      await model.load(level: level, server: song.server(for: level))
    }
  }

  private var closeButton: some View {
    Button {
      dismiss()
    } label: {
      Image(systemName: "xmark")
        .frame(width: 44, height: 44)
        .background(.black.opacity(0.55), in: Circle())
    }
    .accessibilityLabel("Close Preview")
  }

  /// The engine's menu and progress layouts place the close button and
  /// the position slider; hidden layouts fall back to the corners.
  @ViewBuilder private func controls(scene: EnginePreviewScene, size: CGSize)
    -> some View {
    let menu = scene.menu.isVisible ? scene.menu.frame(in: size)
      : CGRect(x: size.width - 64, y: 20, width: 44, height: 44)
    Button {
      dismiss()
    } label: {
      Image(systemName: "xmark")
        .font(.system(size: max(12, min(menu.width, menu.height) * 0.4),
          weight: .semibold))
        .frame(width: menu.width, height: menu.height)
        .background(scene.menu.isVisible && scene.menu.values[8] == 0
          ? .clear : .black.opacity(0.55), in: Circle())
        .contentShape(Rectangle().inset(by: min(0,
          (min(menu.width, menu.height) - 44) / 2)))
    }
    .accessibilityLabel("Close Preview")
    .opacity(scene.menu.isVisible ? min(1, scene.menu.values[7]) : 1)
    .position(x: menu.midX, y: menu.midY)
    if scene.canvas.scrollLength > 0 {
      let bar = scene.progress.isVisible ? scene.progress.frame(in: size)
        : CGRect(x: 20, y: size.height - 64, width: size.width - 40,
          height: 44)
      Slider(value: Binding(get: { model.progress },
        set: { model.seek(toProgress: $0) }))
        .padding(.horizontal, 12)
        .frame(width: bar.width, height: bar.height)
        .background(scene.progress.isVisible && scene.progress.values[8] == 0
          ? .clear : .black.opacity(0.4), in: Capsule())
        .opacity(scene.progress.isVisible
          ? min(1, scene.progress.values[7]) : 1)
        .position(x: bar.midX, y: bar.midY)
        .accessibilityLabel("Chart Position")
        .accessibilityValue(model.progress.formatted(.percent
          .precision(.fractionLength(0))))
    }
  }
}

private struct ChartPreviewCanvas: UIViewRepresentable {
  let scene: EnginePreviewScene
  let model: ChartPreviewModel

  func makeUIView(context: Context) -> ChartPreviewCanvasView {
    let view = ChartPreviewCanvasView()
    view.onScroll = { [weak model] in model?.progress = $0 }
    model.scrollToProgress = { [weak view] in view?.scroll(toProgress: $0) }
    view.show(scene, progress: model.progress)
    return view
  }

  func updateUIView(_ view: ChartPreviewCanvasView, context: Context) {
    view.show(scene, progress: model.progress)
  }
}

/// Draws the scene beneath a transparent scroll view, which supplies native
/// dragging, momentum and bouncing in the canvas's scroll direction.
final class ChartPreviewCanvasView: UIView, UIScrollViewDelegate {
  var onScroll: ((Double) -> Void)?
  private(set) var scene: EnginePreviewScene?
  private(set) var position = 0.0
  private var progress = 0.0
  private let scrollView = UIScrollView()
  private let softwareView = ChartPreviewSoftwareView()
  private let textView = ChartPreviewTextView()
  private var metal: EngineMetalRenderer?
  private var displayLink: CADisplayLink?
  private var needsFrame = false
  private var isConfiguring = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    softwareView.isHidden = true
    for view in [softwareView, textView] {
      view.isUserInteractionEnabled = false
      view.backgroundColor = .clear
      view.isOpaque = false
      addSubview(view)
    }
    textView.contentMode = .redraw
    scrollView.delegate = self
    scrollView.backgroundColor = .clear
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.decelerationRate = .normal
    addSubview(scrollView)
    if let device = MTLCreateSystemDefaultDevice(),
      let renderer = try? EngineMetalRenderer(device: device) {
      metal = renderer
      renderer.onFailure = { [weak self] _ in self?.fallBackToSoftware() }
      layer.insertSublayer(renderer.layer, at: 0)
    } else {
      softwareView.isHidden = false
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func show(_ scene: EnginePreviewScene, progress: Double) {
    guard scene !== self.scene else { return }
    self.scene = scene
    self.progress = progress
    softwareView.sprites = []
    configureScrolling()
  }

  func scroll(toProgress progress: Double) {
    guard let scene, bounds.height > 0 else { return }
    let unit = Double(bounds.height) / 2
    let offset = scene.canvas.contentOffset(
      at: scene.canvas.position(atProgress: progress), pointsPerUnit: unit)
    scrollView.setContentOffset(scene.canvas.isHorizontal
      ? CGPoint(x: offset, y: 0) : CGPoint(x: 0, y: offset), animated: false)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    softwareView.frame = bounds
    textView.frame = bounds
    scrollView.frame = bounds
    metal?.resize(to: bounds.size,
      scale: window?.screen.scale ?? contentScaleFactor)
    configureScrolling()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    displayLink?.invalidate()
    displayLink = nil
    guard window != nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.add(to: .main, forMode: .common)
    displayLink = link
    requestFrame()
  }

  /// Sizes the scroll content to the canvas and restores the position.
  private func configureScrolling() {
    guard let scene, bounds.height > 0 else { return }
    isConfiguring = true
    defer { isConfiguring = false }
    let unit = Double(bounds.height) / 2
    let length = scene.canvas.contentLength(pointsPerUnit: unit)
    let horizontal = scene.canvas.isHorizontal
    scrollView.contentSize = horizontal
      ? CGSize(width: max(length, bounds.width), height: bounds.height)
      : CGSize(width: bounds.width, height: max(length, bounds.height))
    scrollView.alwaysBounceHorizontal = horizontal
    scrollView.alwaysBounceVertical = !horizontal
    position = scene.canvas.position(atProgress: progress)
    let offset = scene.canvas.contentOffset(at: position, pointsPerUnit: unit)
    scrollView.contentOffset = horizontal
      ? CGPoint(x: offset, y: 0) : CGPoint(x: 0, y: offset)
    requestFrame()
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard !isConfiguring, let scene, bounds.height > 0 else { return }
    let offset = scene.canvas.isHorizontal ? scrollView.contentOffset.x
      : scrollView.contentOffset.y
    position = scene.canvas.position(atContentOffset: Double(offset),
      pointsPerUnit: Double(bounds.height) / 2)
    progress = scene.canvas.progress(at: position)
    onScroll?(progress)
    requestFrame()
  }

  private func requestFrame() {
    needsFrame = true
    displayLink?.isPaused = false
  }

  @objc private func tick() {
    guard needsFrame, let scene else {
      displayLink?.isPaused = true
      return
    }
    let sprites = scene.sprites(at: position)
    textView.update(scene: scene, position: position)
    if let metal {
      do {
        // A busy GPU queue skips this tick; the link retries next frame.
        if try metal.draw(sprites, size: bounds.size) { needsFrame = false }
      } catch {
        fallBackToSoftware()
      }
    } else {
      softwareView.sprites = sprites
      softwareView.setNeedsDisplay()
      needsFrame = false
    }
  }

  private func fallBackToSoftware() {
    metal?.onFailure = nil
    metal?.layer.removeFromSuperlayer()
    metal = nil
    softwareView.isHidden = false
    requestFrame()
  }
}

private final class ChartPreviewSoftwareView: UIView {
  var sprites = [EngineRenderSprite]()

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    try? EngineRenderer.draw(sprites, context: context, size: bounds.size)
  }
}

/// Draws `Print` labels above the sprites. Their box, pivot, alignment and
/// background follow the engine; font and colors are host policy.
private final class ChartPreviewTextView: UIView {
  private var prints = [EnginePrintCommand]()
  private var offset = EnginePoint(x: 0, y: 0)

  func update(scene: EnginePreviewScene, position: Double) {
    prints = scene.prints(at: position)
    offset = scene.canvas.offset(at: position)
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    let unit = bounds.height / 2
    for print in prints {
      let width = print.size.x * unit, height = print.size.y * unit
      guard width > 0, height > 0, print.alpha > 0 else { continue }
      context.saveGState()
      defer { context.restoreGState() }
      context.translateBy(x: bounds.midX + (print.anchor.x + offset.x) * unit,
        y: bounds.midY - (print.anchor.y + offset.y) * unit)
      context.rotate(by: -print.rotation)
      context.setAlpha(print.alpha)
      let box = CGRect(x: -print.pivot.x * width,
        y: -(1 - print.pivot.y) * height, width: width, height: height)
      if print.background {
        context.setFillColor(UIColor.black.withAlphaComponent(0.4).cgColor)
        context.addPath(UIBezierPath(roundedRect: box,
          cornerRadius: height / 4).cgPath)
        context.fillPath()
      }
      let text = print.text()
      var font = UIFont.monospacedDigitSystemFont(ofSize: height * 0.8,
        weight: .semibold)
      var attributes: [NSAttributedString.Key: Any] = [.font: font,
        .foregroundColor: color(print.color)]
      var measured = (text as NSString).size(withAttributes: attributes)
      if measured.width > width {
        font = font.withSize(font.pointSize * width / measured.width)
        attributes[.font] = font
        measured = (text as NSString).size(withAttributes: attributes)
      }
      let x = print.horizontalAlign < 0 ? box.minX
        : print.horizontalAlign > 0 ? box.maxX - measured.width
        : box.midX - measured.width / 2
      UIGraphicsPushContext(context)
      (text as NSString).draw(at: CGPoint(x: x,
        y: box.midY - measured.height / 2), withAttributes: attributes)
      UIGraphicsPopContext()
    }
  }

  private func color(_ value: Double) -> UIColor {
    switch value {
    case -1: tintColor
    case 1: .systemRed
    case 2: .systemGreen
    case 3: .systemBlue
    case 4: .systemYellow
    case 5: .systemPurple
    case 6: .systemCyan
    default: .white
    }
  }
}
