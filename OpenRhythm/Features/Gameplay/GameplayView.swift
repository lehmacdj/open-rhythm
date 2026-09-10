import SwiftUI
import UIKit
import Metal

struct GameplayView: View {
  let song: CatalogSong
  let level: SonolusLevelItem
  @State private var model = GameplayModel()
  @State private var showsSettings = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      switch model.phase {
      case .loading:
        ProgressView("Preparing chart…")
      case .ready:
        readyView
      case .playing:
        playfield
      case .finished:
        resultView
      case .failed(let message):
        ContentUnavailableView(
          "Couldn’t Start",
          systemImage: "exclamationmark.triangle",
          description: Text(message)
        )
      }
    }
    .navigationTitle(song.title.displayValue())
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(model.phase == .playing ? .hidden : .visible, for: .navigationBar)
    .statusBarHidden(model.phase == .playing)
    .persistentSystemOverlays(model.phase == .playing ? .hidden : .automatic)
    .sheet(isPresented: $showsSettings) {
      GameplaySettingsPanel(settings: $model.settings,
        noteSpeed: model.presentationAssets?.noteSpeedOption,
        engineName: song.engineName)
    }
    .task {
      await model.prepare(
        level: level,
        server: song.server(for: level),
        title: song.title.displayValue()
      )
    }
    .onDisappear { model.stop() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { model.stop() }
    }
  }

  private var readyView: some View {
    ContentUnavailableView {
      Label("Ready", systemImage: "music.note")
    } description: {
      Text(
        "\(model.noteCount) notes · "
          + "\(level.difficulty.displayName) \(level.rating)"
      )
    } actions: {
      Button("Start", systemImage: "play.fill") {
        model.start()
      }
      .buttonStyle(.borderedProminent)
      Button("Gameplay Settings", systemImage: "slider.horizontal.3") {
        showsSettings = true
      }
    }
  }

  private var playfield: some View {
    ZStack(alignment: .top) {
      GeometryReader { geometry in
        ZStack {
          Color.black
          if model.presentationAssets != nil {
            EnginePlayfield(model: model).id(model.playbackGeneration)
          } else {
            TimelineView(.animation) { _ in
              Canvas { context, size in
                drawPlayfield(context: &context, size: size)
              }
            }
            laneInput
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
      }
      .ignoresSafeArea()
      JudgementOverlay(feedback: model.latestJudgement,
        mode: model.settings.judgementDisplay)
        .padding(.top, 76)
        .allowsHitTesting(false)
      if model.isStartingPlayback {
        ProgressView("Starting chart…")
          .padding()
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
          .frame(maxHeight: .infinity)
      }
      // Controls inherit the outer safe area; only the playfield expands
      // beneath the notch and home indicator.
      HStack {
        Button {
          model.stop()
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.55), in: Circle())
        }
        .accessibilityLabel("Exit Song")
        Spacer()
        VStack(spacing: 2) {
          Text("Score \(model.displayedScore)")
          Text("Combo \(model.combo)")
        }
        .allowsHitTesting(false)
        Spacer()
        Button {
          model.restart()
        } label: {
          Image(systemName: "arrow.counterclockwise")
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.55), in: Circle())
        }
        .accessibilityLabel("Restart Song")
      }
      .font(.headline.monospacedDigit())
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .padding(.top, 8)
    }
  }

  private var laneInput: some View {
    LaneInput(model: model)
  }

  private var resultView: some View {
    Form {
      Section("Result") {
        LabeledContent("Score", value: model.score.formatted())
        LabeledContent("Max Combo", value: model.maxCombo.formatted())
      }
      Section("Judgements") {
        ForEach(NoteJudgement.allCases, id: \.self) { judgement in
          LabeledContent(
            judgement.displayName,
            value: model.judgements[judgement, default: 0].formatted()
          )
        }
      }
      Section {
        Button("Done") {
          Task {
            await model.resultSaveTask?.value
            if model.resultSaveError == nil { dismiss() }
          }
        }
      }
      if let error = model.resultSaveError {
        Section("Couldn’t Save Result") {
          Text(error)
        }
      }
    }
  }

  private func drawPlayfield(
    context: inout GraphicsContext,
    size: CGSize
  ) {
    let targetY = size.height * 0.82
    let laneWidth = size.width / 9
    let pixelsPerSecond = size.height * 0.32

    for lane in 0...9 {
      let x = CGFloat(lane) * laneWidth
      var path = Path()
      path.move(to: CGPoint(x: x, y: 0))
      path.addLine(to: CGPoint(x: x, y: size.height))
      context.stroke(path, with: .color(.white.opacity(0.12)))
    }

    var target = Path()
    target.move(to: CGPoint(x: 0, y: targetY))
    target.addLine(to: CGPoint(x: size.width, y: targetY))
    context.stroke(target, with: .color(.white), lineWidth: 2)

    for note in model.chart.notes {
      let isActiveHold = model.activeHoldIDs.contains(note.id)
      guard !model.hitNoteIDs.contains(note.id) || isActiveHold else {
        continue
      }
      let delta = note.time - model.currentTime
      guard delta > -0.2 || isActiveHold, delta < 3 else { continue }
      let x = (CGFloat(note.lane + 4) + 0.5) * laneWidth
      let y = isActiveHold
        ? targetY
        : targetY - CGFloat(delta) * pixelsPerSecond
      let radius = max(10, laneWidth * 0.32)

      if let endTime = note.endTime {
        let endY = targetY
          - CGFloat(endTime - model.currentTime) * pixelsPerSecond
        var hold = Path()
        hold.move(to: CGPoint(x: x, y: y))
        hold.addLine(to: CGPoint(x: x, y: endY))
        context.stroke(
          hold,
          with: .color(.cyan.opacity(0.7)),
          lineWidth: radius * 0.8
        )
      }

      let rect = CGRect(
        x: x - radius,
        y: y - radius,
        width: radius * 2,
        height: radius * 2
      )
      let color: Color = switch note.kind {
      case .tap: .pink
      case .swing: .orange
      case .hold: .cyan
      }
      context.fill(Path(ellipseIn: rect), with: .color(color))
      context.stroke(
        Path(ellipseIn: rect),
        with: .color(.white),
        lineWidth: 2
      )
    }
  }
}

private struct GameplaySettingsPanel: View {
  @Binding var settings: GameplayPreferences
  let noteSpeed: EngineConfiguration.Option?
  let engineName: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(engineName)
          Text("These preferences are saved for this engine.")
            .foregroundStyle(.secondary)
        }
        Section("Score Display") {
          Picker("Direction", selection: $settings.scoreDisplay) {
            ForEach(ScoreDisplayMode.allCases) { Text($0.title).tag($0) }
          }
          Text("Count up shows points earned toward 1,000,000. Count down starts at 1,000,000 and subtracts lost points. Final results are unchanged.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Hit Feedback") {
          Picker("Display", selection: $settings.judgementDisplay) {
            ForEach(JudgementDisplayMode.allCases) { Text($0.title).tag($0) }
          }
          Text("Early/Late shows timing for GREAT and GOOD judgements.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Note Speed") {
          if let noteSpeed, let range = noteSpeed.sliderRange {
            let value = noteSpeed.clamped(settings.noteSpeed ?? noteSpeed.def)
            LabeledContent("Speed", value: value.formatted(.number.precision(.fractionLength(1))))
            Slider(value: Binding(get: { value }, set: { settings.noteSpeed = $0 }),
              in: range, step: (noteSpeed.step ?? 0.1) > 0 ? (noteSpeed.step ?? 0.1) : 0.1)
              .accessibilityLabel("Note Speed")
            Button("Use Engine Default") { settings.noteSpeed = nil }
          } else {
            Text("This engine does not expose a note-speed control.")
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Gameplay Settings")
      .toolbar { Button("Done") { dismiss() } }
    }
  }
}

private struct JudgementOverlay: View {
  let feedback: JudgementFeedback?
  let mode: JudgementDisplayMode
  @State private var visible = false

  var body: some View {
    Text(feedback?.text(for: mode) ?? "")
      .font(.title2.bold().monospaced())
      .foregroundStyle(.white)
      .shadow(color: .black, radius: 3)
      .opacity(visible && mode != .off ? 1 : 0)
      .task(id: feedback) {
        visible = feedback != nil
        do {
          try await Task.sleep(for: .milliseconds(650))
          visible = false
        } catch { }
      }
  }
}

private struct EnginePlayfield: UIViewRepresentable {
  let model: GameplayModel

  func makeUIView(context: Context) -> EnginePlayfieldView {
    let view = EnginePlayfieldView()
    view.model = model
    view.prepareAssets()
    view.isMultipleTouchEnabled = true
    view.backgroundColor = .black
    view.isOpaque = true
    return view
  }

  func updateUIView(_ view: EnginePlayfieldView, context: Context) {
    view.model = model
  }
}

private final class EnginePlayfieldView: UIView {
  weak var model: GameplayModel?
  private var displayLink: CADisplayLink?
  private var touchesByID = [ObjectIdentifier: EngineTouch]()
  private var nextTouchID = 1
  private var metal: EngineMetalRenderer?

  override init(frame: CGRect) {
    super.init(frame: frame)
    if let device = MTLCreateSystemDefaultDevice(),
      let renderer = try? EngineMetalRenderer(device: device) {
      metal = renderer
      layer.addSublayer(renderer.layer)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func prepareAssets() {
    guard let assets = model?.presentationAssets else { return }
    do {
      try metal?.prepare(assets)
    } catch {
      metal?.layer.removeFromSuperlayer()
      metal = nil
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    metal?.resize(to: bounds.size, scale: window?.screen.scale ?? contentScaleFactor)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    displayLink?.invalidate()
    displayLink = nil
    if window != nil {
      let link = CADisplayLink(target: self, selector: #selector(updateFrame))
      link.add(to: .main, forMode: .common)
      displayLink = link
    }
  }

  @objc private func updateFrame() {
    advanceFrame(present: true)
  }

  private func advanceFrame(present: Bool) {
    let sampleTime = model?.playbackTime ?? 0
    model?.engineFrame(size: bounds.size,
      touches: touchesByID.values.sorted { $0.id < $1.id })
    touchesByID = touchesByID.filter { !$0.value.ended }.mapValues {
      $0.nextFrame(at: sampleTime)
    }
    guard present else { return }
    if let metal, let runtime = model?.engineRuntime,
      let assets = model?.presentationAssets {
      do {
        try metal.draw(host: runtime.host, assets: assets, size: bounds.size)
      } catch {
        // Keep a functioning software path if this device cannot render Metal.
        metal.layer.removeFromSuperlayer()
        self.metal = nil
        setNeedsDisplay()
      }
    } else if metal == nil {
      setNeedsDisplay()
    }
  }

  override func draw(_ rect: CGRect) {
    guard metal == nil, let runtime = model?.engineRuntime,
      let assets = model?.presentationAssets,
      let context = UIGraphicsGetCurrentContext() else { return }
    UIColor.black.setFill()
    context.fill(bounds)
    EngineRenderer.draw(host: runtime.host, assets: assets,
      context: context, size: bounds.size)
  }

  private func receive(_ touches: Set<UITouch>, started: Bool, ended: Bool) {
    guard bounds.height > 0, let model, !model.isStartingPlayback else { return }
    for touch in touches {
      let key = ObjectIdentifier(touch)
      let previous = touchesByID[key]
      guard started || previous != nil else { continue }
      let point = touch.location(in: self)
      let position = EnginePoint(
        x: (point.x - bounds.midX) * 2 / bounds.height,
        y: (bounds.midY - point.y) * 2 / bounds.height
      )
      let time = model.playbackTime
        + touch.timestamp - ProcessInfo.processInfo.systemUptime
      let id = previous?.id ?? nextTouchID
      if previous == nil { nextTouchID += 1 }
      touchesByID[key] = previous?.moved(to: position, at: time, ended: ended)
        ?? EngineTouch(
        id: id, started: started, ended: ended, time: time,
        startTime: previous?.startTime ?? time, position: position,
        startPosition: previous?.startPosition ?? position,
        delta: EnginePoint(x: position.x - (previous?.position.x ?? position.x),
          y: position.y - (previous?.position.y ?? position.y))
      )
    }
    // Pool events until the next display tick. Started and ended can both be
    // true, preserving short taps without running the entire engine per event.
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    receive(touches, started: true, ended: false)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    receive(touches, started: false, ended: false)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    receive(touches, started: false, ended: true)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    receive(touches, started: false, ended: true)
  }
}

private struct LaneInput: UIViewRepresentable {
  let model: GameplayModel

  func makeUIView(context: Context) -> LaneInputView {
    let view = LaneInputView()
    view.isMultipleTouchEnabled = true
    view.backgroundColor = .clear
    view.model = model
    return view
  }

  func updateUIView(_ view: LaneInputView, context: Context) {
    view.model = model
  }
}

private final class LaneInputView: UIView {
  var model: GameplayModel?
  private var lanes = [ObjectIdentifier: Int]()

  private func lane(for touch: UITouch) -> Int? {
    let point = touch.location(in: self)
    guard bounds.width > 0, bounds.contains(point) else { return nil }
    return min(8, Int(point.x / bounds.width * 9)) - 4
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      guard let lane = lane(for: touch) else { continue }
      let occupied = lanes.values.contains(lane)
      lanes[ObjectIdentifier(touch)] = lane
      if !occupied { model?.press(lane: lane) }
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      let id = ObjectIdentifier(touch)
      let next = lane(for: touch)
      guard lanes[id] != next else { continue }
      release(id)
      if let next {
        lanes[id] = next
        model?.slide(lane: next)
      }
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches { release(ObjectIdentifier(touch)) }
  }

  override func touchesCancelled(
    _ touches: Set<UITouch>, with event: UIEvent?
  ) {
    for touch in touches { release(ObjectIdentifier(touch)) }
  }

  private func release(_ id: ObjectIdentifier) {
    guard let lane = lanes.removeValue(forKey: id),
      !lanes.values.contains(lane)
    else { return }
    model?.release(lane: lane)
  }
}
