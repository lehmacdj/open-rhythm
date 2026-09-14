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
        scoreMode: model.presentationAssets?.scoreModeOption,
        options: model.presentationAssets?.configuration.options ?? [])
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
          + "\(level.difficulty.displayName) \(level.rating.formatted())"
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
            if model.engineUI.count == 8 {
              engineHUD(size: geometry.size)
                .allowsHitTesting(false)
            }
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
      if model.presentationAssets == nil {
        JudgementOverlay(feedback: model.latestJudgement,
          mode: model.settings.judgementDisplay)
          .padding(.top, 76)
          .allowsHitTesting(false)
      }
      if model.isStartingPlayback {
        ProgressView("Starting chart…")
          .padding()
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
          .frame(maxHeight: .infinity)
      }
      // Controls inherit the outer safe area; only the playfield expands
      // beneath the notch and home indicator.
      if model.presentationAssets != nil {
        HStack {
          Spacer()
          Menu {
            Button("Restart Song", systemImage: "arrow.counterclockwise") {
              model.restart()
            }
            Button("Exit Song", systemImage: "xmark") {
              model.stop()
              dismiss()
            }
          } label: {
            Image(systemName: "ellipsis")
              .frame(width: 44, height: 44)
              .background(.black.opacity(0.55), in: Circle())
          }
          .accessibilityLabel("Song Controls")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 8)
      } else {
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
  }

  private var laneInput: some View {
    LaneInput(model: model)
  }

  private func engineHUD(size: CGSize) -> some View {
    ZStack(alignment: .topLeading) {
      EngineUIPlacement(element: model.engineUI[1], size: size) {
        JudgementOverlay(feedback: model.latestJudgement,
          mode: model.settings.judgementDisplay,
          animation: model.presentationAssets?.ui?.judgmentAnimation,
          timingPlacement: model.presentationAssets?.ui?.judgmentErrorPlacement,
          timingStyle: model.presentationAssets?.ui?.judgmentErrorStyle,
          fontSize: model.engineUI[1].values[5] * size.height / 2)
      }
      if model.combo > 0 {
        EngineUIPlacement(element: model.engineUI[2], size: size) {
          EngineComboText(combo: model.combo,
            animation: model.presentationAssets?.ui?.comboAnimation)
        }
        EngineUIPlacement(element: model.engineUI[3], size: size) {
          EngineComboText(combo: model.combo, isLabel: true,
            animation: model.presentationAssets?.ui?.comboAnimation)
        }
      }
      metricUI(model.presentationAssets?.ui?.primaryMetric ?? "arcade",
        index: 4, size: size)
      metricUI(model.presentationAssets?.ui?.secondaryMetric ?? "life",
        index: 6, size: size)
    }
    .foregroundStyle(.white)
  }

  @ViewBuilder private func metricUI(_ name: String, index: Int, size: CGSize)
    -> some View {
    let metric = model.engineMetric(name)
    EngineUIPlacement(element: model.engineUI[index], size: size) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Rectangle().fill(.white.opacity(0.2))
          Rectangle().fill(name == "life" ? Color.green : Color.cyan)
            .frame(width: geometry.size.width * (metric?.fraction ?? 0))
        }
      }
      .frame(width: max(0, model.engineUI[index].values[4] * size.height / 2),
        height: max(0, model.engineUI[index].values[5] * size.height / 2))
    }
    EngineUIPlacement(element: model.engineUI[index + 1], size: size) {
      Text(metric?.text ?? "—")
        .accessibilityLabel(metric == nil ? "Unsupported metric: \(name)" : name)
    }
  }

  private var resultView: some View {
    Form {
      Section("Result") {
        LabeledContent("Score", value: model.score.formatted())
        if let accuracy = model.accuracyScore {
          LabeledContent("Accuracy Score", value: accuracy.formatted())
        }
        LabeledContent("Max Combo", value: model.maxCombo.formatted())
        if let life = model.engineLife {
          LabeledContent("Life", value: "\(life.value.formatted()) / \(life.maximum.formatted())")
          LabeledContent("Clear", value: life.failed ? "Failed" : "Passed")
        }
      }
      Section("Judgements") {
        ForEach(NoteJudgement.allCases, id: \.self) { judgement in
          LabeledContent(
            judgement.displayName,
            value: model.judgements[judgement, default: 0].formatted()
          )
        }
      }
      ModifiedEngineOptionsSection(options: model.modifiedOptions)
      ResultStatisticsSections(samples: model.noteTimings,
        duration: model.currentTime)
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
  let scoreMode: EngineConfiguration.Option?
  let options: [EngineConfiguration.Option]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Score Display") {
          if let option = scoreMode, let values = option.values {
            Picker("Engine Score Mode", selection: Binding(
              get: { option.selectedIndex(settings.scoreMode) ?? 0 },
              set: { settings.scoreMode = $0 })) {
              ForEach(values.indices, id: \.self) { index in
                Text(values[index].displayValue()).tag(index)
              }
            }
            Button("Use Engine Default Score Mode") { settings.scoreMode = nil }
          }
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
          Text("Early/Late uses the engine’s timing-display threshold, including qualifying PERFECT judgements.")
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
        ForEach(options.indices, id: \.self) { index in
          let option = options[index]
          if let name = option.name,
            !option.usesNoteSpeedControl, !option.usesScoreModeControl {
            Section(option.displayName) {
              engineOption(option, name: name)
              if let description = option.description, !description.isEmpty {
                Text(EngineConfiguration.Option.label(description))
                  .font(.footnote).foregroundStyle(.secondary)
              }
              if option.standard == true {
                Text("Changes gameplay; recorded with your result.")
                  .font(.footnote).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .navigationTitle("Gameplay Settings")
      .toolbar { Button("Done") { dismiss() } }
    }
  }

  @ViewBuilder private func engineOption(_ option: EngineConfiguration.Option,
    name: String) -> some View {
    let value = option.value(settings.engineOptions[name])
    Group {
      switch option.controlType {
      case "toggle":
        Toggle(option.displayName, isOn: Binding(get: { value != 0 },
          set: { settings.engineOptions[name] = $0 ? 1 : 0 }))
      case "select":
        if let values = option.values {
          Picker(option.displayName, selection: Binding(get: { value },
            set: { settings.engineOptions[name] = $0 })) {
            ForEach(values.indices, id: \.self) { index in
              Text(option.valueLabel(Double(index))).tag(Double(index))
            }
          }
        }
      case "slider":
        if let range = option.sliderRange {
          LabeledContent(option.displayName, value: option.valueLabel(value))
          Slider(value: Binding(get: { value },
            set: { settings.engineOptions[name] = option.clamped($0) }), in: range)
            .accessibilityLabel(option.displayName)
        }
      default:
        Text("Unsupported option type: \(option.type ?? "unknown")")
          .foregroundStyle(.secondary)
      }
      if option.controlType != nil {
        Button("Use Engine Default") { settings.engineOptions[name] = nil }
          .disabled(settings.engineOptions[name] == nil)
      }
    }
  }
}

struct ModifiedEngineOptionsSection: View {
  let options: [EngineOptionOverride]

  var body: some View {
    if !options.isEmpty {
      Section("Modified Gameplay") {
        ForEach(options.indices, id: \.self) { index in
          LabeledContent(options[index].name, value: options[index].value)
        }
      }
    }
  }
}

private struct JudgementOverlay: View {
  let feedback: JudgementFeedback?
  let mode: JudgementDisplayMode
  var animation: EngineConfiguration.UI.Animation? = nil
  var timingPlacement: String? = nil
  var timingStyle: String? = nil
  var fontSize: CGFloat? = nil
  @State private var visible = false
  @State private var isAnimating = false
  @State private var started = Date()

  var body: some View {
    TimelineView(.animation(paused: !isAnimating)) { context in
      let elapsed = isAnimating ? max(0, context.date.timeIntervalSince(started))
        : animation?.duration ?? 0.65
      JudgementLabel(feedback: feedback, mode: mode, fontSize: fontSize,
        timingPlacement: timingPlacement, timingStyle: timingStyle)
        .scaleEffect(animation?.scale.value(at: elapsed) ?? 1)
        .opacity(visible && mode != .off
          ? min(1, max(0, animation?.alpha.value(at: elapsed) ?? 1)) : 0)
    }
      .task(id: feedback) {
        started = Date()
        visible = feedback != nil
        isAnimating = visible
        do {
          try await Task.sleep(for: .seconds(animation?.duration ?? 0.65))
          isAnimating = false
          // Engine animations own their final alpha; a tween ending at one
          // keeps the grade visible, rather than imposing our own timeout.
          if animation == nil { visible = false }
        } catch { }
      }
  }
}

private struct EngineComboText: View {
  let combo: Int
  var isLabel = false
  let animation: EngineConfiguration.UI.Animation?
  @State private var started = Date()
  @State private var isAnimating = false

  var body: some View {
    TimelineView(.animation(paused: !isAnimating)) { context in
      let elapsed = isAnimating ? max(0, context.date.timeIntervalSince(started))
        : animation?.duration ?? 0
      Text(isLabel ? "COMBO" : combo.formatted())
        .scaleEffect(animation?.scale.value(at: elapsed) ?? 1)
        .opacity(min(1, max(0, animation?.alpha.value(at: elapsed) ?? 1)))
    }
    .task(id: combo) {
      guard let animation else { return }
      started = Date()
      isAnimating = true
      do {
        try await Task.sleep(for: .seconds(animation.duration))
        isAnimating = false
      } catch { }
    }
  }
}

private struct JudgementLabel: View {
  let feedback: JudgementFeedback?
  let mode: JudgementDisplayMode
  var fontSize: CGFloat? = nil
  var timingPlacement: String? = nil
  var timingStyle: String? = nil

  var body: some View {
    JudgmentTimingLayout(placement: feedback?.timingPlacement(timingPlacement) ?? "top") {
      Text(feedback?.judgement.rawValue.uppercased() ?? "")
        .font(fontSize.map { .system(size: $0, weight: .bold, design: .monospaced) }
          ?? .title2.bold().monospaced())
      Text(feedback?.timingText(for: mode, style: timingStyle) ?? "")
        .font(fontSize.map { .system(size: $0 * 0.5, weight: .bold) } ?? .caption.bold())
    }
      .foregroundStyle(.white)
      .shadow(color: .black, radius: 3)
  }
}

/// Keep the grade itself on the engine's anchor. Adding or moving the smaller
/// timing label must not shift PERFECT/GREAT/GOOD between successive hits.
private struct JudgmentTimingLayout: Layout {
  let placement: String

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
    cache: inout ()) -> CGSize {
    subviews.first?.sizeThatFits(.unspecified) ?? .zero
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
    subviews: Subviews, cache: inout ()) {
    guard subviews.count == 2 else { return }
    subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.midY),
      anchor: .center, proposal: .unspecified)
    let point: CGPoint
    let anchor: UnitPoint
    switch placement {
    case "bottom": point = CGPoint(x: bounds.midX, y: bounds.maxY + 2); anchor = .top
    case "left": point = CGPoint(x: bounds.minX - 4, y: bounds.midY); anchor = .trailing
    case "right": point = CGPoint(x: bounds.maxX + 4, y: bounds.midY); anchor = .leading
    case "center": point = CGPoint(x: bounds.midX, y: bounds.midY); anchor = .center
    default: point = CGPoint(x: bounds.midX, y: bounds.minY - 2); anchor = .bottom
    }
    subviews[1].place(at: point, anchor: anchor, proposal: .unspecified)
  }
}

private struct EngineUIPlacement<Content: View>: View {
  let element: EngineUIElement
  let size: CGSize
  @ViewBuilder let content: Content

  var body: some View {
    if element.isVisible {
      EngineAnchorLayout(element: element, size: size) {
        content
          .font(.system(size: element.values[5] * size.height / 2,
            weight: .bold, design: .rounded).monospacedDigit())
          .fixedSize()
          .frame(width: element.values[4] > 0
            ? element.values[4] * size.height / 2 : nil,
            alignment: element.values[8] < 0 ? .leading
              : element.values[8] > 0 ? .trailing : .center)
          .background(element.values[9] != 0 ? Color.black.opacity(0.4) : .clear)
          .opacity(min(1, element.values[7]))
          .rotationEffect(.radians(-element.values[6]),
            anchor: UnitPoint(x: element.pivot.x, y: element.pivot.y))
      }
    }
  }
}

private struct EngineAnchorLayout: Layout {
  let element: EngineUIElement
  let size: CGSize

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
    cache: inout ()) -> CGSize { size }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
    subviews: Subviews, cache: inout ()) {
    let anchor = element.anchor(in: size)
    for subview in subviews {
      subview.place(at: CGPoint(x: bounds.minX + anchor.x, y: bounds.minY + anchor.y),
        anchor: UnitPoint(x: element.pivot.x, y: element.pivot.y),
        proposal: .unspecified)
    }
  }
}

#Preview("Timing Feedback") {
  ZStack {
    Color.black
    JudgementLabel(feedback: JudgementFeedback(sequence: 1,
      judgement: .perfect, accuracy: -0.03, minimumError: 0.02), mode: .timing)
  }
}

#Preview("Engine Options") {
  let configuration = try! JSONDecoder().decode(EngineConfiguration.self,
    from: Data(#"""
    {"options":[
    {"name":"#SPEED","type":"slider","def":1,"min":0.5,"max":2,
     "step":0.05,"unit":"#PERCENTAGE_UNIT","standard":true},
    {"name":"#MIRROR","type":"toggle","def":0,"standard":true},
    {"name":"Input Mode","type":"select","def":0,
     "values":["Normal","Strict"]}]}
    """#.utf8))
  GameplaySettingsPanel(settings: .constant(GameplayPreferences()),
    noteSpeed: nil, scoreMode: nil, options: configuration.options)
}

#Preview("Engine Timing Positions", traits: .fixedLayout(width: 420, height: 280)) {
  ZStack {
    Color.black
    VStack(spacing: 65) {
      VStack(spacing: 20) {
        Text("Project SEKAI · top").font(.caption)
        JudgementLabel(feedback: JudgementFeedback(sequence: 1,
          judgement: .perfect, accuracy: -0.03, minimumError: 0.02),
          mode: .timing, timingPlacement: "top")
      }
      VStack(spacing: 20) {
        Text("Love Live · bottom").font(.caption)
        JudgementLabel(feedback: JudgementFeedback(sequence: 2,
          judgement: .great, accuracy: 0.04, minimumError: 0.02),
          mode: .timing, timingPlacement: "bottom")
      }
    }.foregroundStyle(.white)
  }
}

#Preview("Engine Timing Styles", traits: .fixedLayout(width: 800, height: 750)) {
  ZStack {
    Color.black
    Grid(horizontalSpacing: 55, verticalSpacing: 24) {
      GridRow {
        Text("Style")
        Text("Positive error")
        Text("Negative error")
      }
      ForEach(EngineJudgmentErrorStyle.allCases, id: \.self) { style in
        GridRow {
          Text(style.rawValue).font(.caption.monospaced())
          ForEach([1.0, -1.0], id: \.self) { sign in
            JudgementLabel(feedback: JudgementFeedback(sequence: 1,
              judgement: .perfect, accuracy: sign * 0.03, minimumError: 0.02),
              mode: .timing, fontSize: 20, timingPlacement: "top",
              timingStyle: style.rawValue)
          }
        }
      }
    }.foregroundStyle(.white)
  }
}

#Preview("Engine HUD Layout", traits: .fixedLayout(width: 844, height: 390)) {
  let memory = EngineMemory()
  let placements = [
    [-1.9, 0.85, 0, 1, 0.75, 0.15, 0, 1, -1, 0],
    [-1.185, 0.815, 1, 1, 0, 0.08, 0, 1, 1, 0],
    [1.9, 0.85, 1, 1, 0.75, 0.15, 0, 1, 1, 0],
    [1.865, 0.815, 1, 1, 0, 0.08, 0, 1, 1, 0],
    [0, -0.23, 0.5, 0.5, 0, 0.095, 0, 1, 0, 0],
    [1.065, 0.175, 0.5, 0.5, 0, 0.28, 0, 1, 0, 0],
    [1.065, 0.175, 0.5, -2.25, 0, 0.07, 0, 1, 0, 0]
  ]
  let _ = placements.enumerated().forEach { row, values in
    values.enumerated().forEach { index, value in
      memory.set(block: 1006, index: row * 10 + index, value: value)
    }
  }
  ZStack(alignment: .topLeading) {
    Color.black
    ForEach(0..<7) { index in
      let element = EngineUIElement(memory: memory, index: index)
      EngineUIPlacement(element: element, size: CGSize(width: 844, height: 390)) {
        if index == 0 || index == 2 {
          Rectangle().fill(index == 0 ? Color.cyan.opacity(0.4) : Color.green.opacity(0.4))
            .frame(width: 146.25, height: 29.25)
        } else if index == 4 {
          JudgementLabel(feedback: JudgementFeedback(sequence: 1,
            judgement: .perfect, accuracy: -0.03, minimumError: 0.02),
            mode: .timing, fontSize: 18.525)
        } else {
          Text(index == 1 ? "975,430" : index == 3 ? "1,000"
            : index == 5 ? "123" : "COMBO")
        }
      }
    }
  }.foregroundStyle(.white)
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
  private var touchPool = EngineTouchPool<ObjectIdentifier>()
  private var metal: EngineMetalRenderer?
  private let backgroundLayer = EngineBackgroundLayer()
  private let softwareSurface = EngineSoftwareSurfaceView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.addSublayer(backgroundLayer.layer)
    softwareSurface.isUserInteractionEnabled = false
    softwareSurface.backgroundColor = .clear
    softwareSurface.isOpaque = false
    addSubview(softwareSurface)
    if let device = MTLCreateSystemDefaultDevice(),
      let renderer = try? EngineMetalRenderer(device: device) {
      metal = renderer
      layer.addSublayer(renderer.layer)
      softwareSurface.isHidden = true
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func prepareAssets() {
    guard let assets = model?.presentationAssets else { return }
    backgroundLayer.prepare(assets.background)
    softwareSurface.model = model
    do {
      try metal?.prepare(assets)
    } catch {
      metal?.layer.removeFromSuperlayer()
      metal = nil
      softwareSurface.isHidden = false
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    softwareSurface.frame = bounds
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
      touches: touchPool.touches, safeAreaInsets: safeAreaInsets)
    touchPool.nextFrame(at: sampleTime)
    guard present, model?.isStartingPlayback == false else { return }
    if let memory = model?.engineRuntime?.memory {
      backgroundLayer.update(quad: (0..<8).map { memory.value(block: 1005, index: $0) },
        size: bounds.size)
    }
    if let metal, let runtime = model?.engineRuntime,
      let assets = model?.presentationAssets {
      do {
        try metal.draw(host: runtime.host, assets: assets, size: bounds.size)
      } catch {
        // Keep a functioning software path if this device cannot render Metal.
        metal.layer.removeFromSuperlayer()
        self.metal = nil
        softwareSurface.isHidden = false
        softwareSurface.setNeedsDisplay()
      }
    } else if metal == nil {
      softwareSurface.setNeedsDisplay()
    }
  }

  private func receive(_ touches: Set<UITouch>, started: Bool, ended: Bool) {
    guard bounds.height > 0, let model, !model.isStartingPlayback else { return }
    for touch in touches {
      let key = ObjectIdentifier(touch)
      let point = touch.location(in: self)
      let position = EnginePoint(
        x: (point.x - bounds.midX) * 2 / bounds.height,
        y: (bounds.midY - point.y) * 2 / bounds.height
      )
      let time = model.inputTime(at: touch.timestamp)
      touchPool.receive(key: key, position: position, time: time,
        started: started, ended: ended)
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

private final class EngineSoftwareSurfaceView: UIView {
  weak var model: GameplayModel?

  override func draw(_ rect: CGRect) {
    guard let runtime = model?.engineRuntime,
      let assets = model?.presentationAssets,
      let context = UIGraphicsGetCurrentContext() else { return }
    do {
      try EngineRenderer.draw(host: runtime.host, assets: assets,
        context: context, size: bounds.size)
    } catch {
      model?.renderingFailed(error)
    }
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
      if !occupied {
        model?.press(lane: lane, at: model?.inputTime(at: touch.timestamp))
      }
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      let id = ObjectIdentifier(touch)
      let next = lane(for: touch)
      guard lanes[id] != next else { continue }
      release(id, at: touch.timestamp)
      if let next {
        lanes[id] = next
        model?.slide(lane: next, at: model?.inputTime(at: touch.timestamp))
      }
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches { release(ObjectIdentifier(touch), at: touch.timestamp) }
  }

  override func touchesCancelled(
    _ touches: Set<UITouch>, with event: UIEvent?
  ) {
    for touch in touches { release(ObjectIdentifier(touch), at: touch.timestamp) }
  }

  private func release(_ id: ObjectIdentifier, at timestamp: TimeInterval) {
    guard let lane = lanes.removeValue(forKey: id),
      !lanes.values.contains(lane)
    else { return }
    model?.release(lane: lane, at: model?.inputTime(at: timestamp))
  }
}
