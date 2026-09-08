import SwiftUI
import UIKit

struct GameplayView: View {
  let song: CatalogSong
  let level: SonolusLevelItem
  @State private var model = GameplayModel()
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
        "\(model.chart.judgementCount) notes · "
          + "\(level.difficulty.displayName) \(level.rating)"
      )
    } actions: {
      Button("Start", systemImage: "play.fill") {
        model.start()
      }
      .buttonStyle(.borderedProminent)
    }
  }

  private var playfield: some View {
    GeometryReader { geometry in
      ZStack {
        Color.black.ignoresSafeArea()
        TimelineView(.animation) { _ in
          Canvas { context, size in
            drawPlayfield(context: &context, size: size)
          }
        }
        laneInput
        VStack {
          HStack {
            Text("Score \(model.score)")
            Spacer()
            Text("Combo \(model.combo)")
          }
          .font(.headline.monospacedDigit())
          .foregroundStyle(.white)
          .padding()
          Spacer()
        }
        .allowsHitTesting(false)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
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
