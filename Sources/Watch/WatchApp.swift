import SwiftUI

@main struct WorkoutZonesWatchApp: App {
  @State private var recorder = WorkoutRecorder()
  var body: some Scene { WindowGroup { RecorderView(recorder: recorder) } }
}

struct RecorderView: View {
  @Bindable var recorder: WorkoutRecorder
  @State private var confirmEnd = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          switch recorder.phase {
          case .ready:
            Image(systemName: "figure.run").font(.largeTitle).foregroundStyle(.mint)
            Text("Outdoor run").font(.headline)
            Text("Record on your watch. Review your zones on iPhone.").font(.footnote)
              .foregroundStyle(.secondary)
            Button("Start workout", systemImage: "play.fill") { Task { await recorder.start() } }
              .tint(.mint)
            Toggle("Zone haptics", isOn: $recorder.haptics)
            Button("Explore preview") { recorder.startPreview() }.accessibilityIdentifier("preview")
          case .preparing, .saving:
            ProgressView(recorder.phase == .preparing ? "Preparing workout" : "Finishing workout")
          case .saved:
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.mint)
            Text("Saved to Health").font(.headline)
            Text("Your iPhone history updates after Health finishes syncing.").font(.footnote)
            Button("Done") { recorder.reset() }
          case .running, .paused:
            if recorder.preview { Text("PREVIEW").font(.caption.bold()).foregroundStyle(.orange) }
            Text(recorder.phase == .paused ? "Paused" : "Outdoor run").font(.headline)
            Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond))).font(
              .title2.monospacedDigit())
            TimelineView(.periodic(from: .now, by: 1)) { context in
              let fresh =
                recorder.preview
                || recorder.sampleDate.map { context.date.timeIntervalSince($0) < 15 } == true
              HStack(alignment: .firstTextBaseline) {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
                Text(fresh ? recorder.heartRate.map { String(Int($0.rounded())) } ?? "—" : "—")
                  .font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                Text("bpm").font(.caption)
              }
            }
            Text(recorder.currentZone.map { "Zone \($0 + 1)" } ?? "Waiting for zones").font(
              .title3.bold()
            ).foregroundStyle(.mint)
            if let summary = recorder.summary {
              ForEach(summary.bands) { band in
                HStack {
                  Text(band.title)
                  Spacer()
                  Text(Duration.seconds(band.seconds).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
                }.font(.caption)
              }
            }
            Text(recorder.source).font(.caption2).foregroundStyle(.secondary)
            Button(recorder.phase == .paused ? "Resume" : "Pause") { recorder.pauseOrResume() }
            Button(recorder.preview ? "Close preview" : "End workout", role: .destructive) {
              if recorder.preview { recorder.finish(save: false) } else { confirmEnd = true }
            }
          }
        }.padding(.horizontal, 4)
      }.navigationTitle("Workout Zones")
    }
    .confirmationDialog("Finish workout?", isPresented: $confirmEnd) {
      Button("Save workout") { recorder.finish(save: true) }
      Button("Discard workout", role: .destructive) { recorder.finish(save: false) }
    }
    .alert(
      "Workout unavailable",
      isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })
    ) {
      Button("OK") { recorder.error = nil }
    } message: {
      Text(recorder.error ?? "")
    }
  }
}
