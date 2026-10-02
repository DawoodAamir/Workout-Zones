import Charts
import HealthKit
import Observation
import SwiftUI

struct WorkoutRecord: Identifiable, Sendable {
  let id: UUID
  let date: Date
  let duration: TimeInterval
  let zones: ZoneSummary?
  let source: String
  static let preview = WorkoutRecord(
    id: UUID(), date: Date(timeIntervalSince1970: 1_790_892_000), duration: 1800, zones: .preview,
    source: "Sample boundaries")
}

@MainActor @Observable final class WorkoutHistory {
  private(set) var workouts: [WorkoutRecord] = []
  private(set) var loading = false
  private(set) var connected = false
  var error: String?
  private let store = HKHealthStore()
  private var generation = 0
  func connect() async {
    guard !loading else { return }
    loading = true
    defer { loading = false }
    do {
      guard HKHealthStore.isHealthDataAvailable() else { throw HistoryError.unavailable }
      try await store.requestAuthorization(
        toShare: [], read: [HKObjectType.workoutType(), HKQuantityType(.heartRate)])
      connected = true
      try await fetch()
    } catch is CancellationError {} catch { self.error = error.localizedDescription }
  }
  func refresh() async {
    guard connected, !loading else { return }
    loading = true
    defer { loading = false }
    do { try await fetch() } catch is CancellationError {} catch {
      self.error = error.localizedDescription
    }
  }
  private func fetch() async throws {
    generation += 1
    let request = generation
    let predicate = HKQuery.predicateForWorkouts(with: .running)
    let sources = try await HKSourceQueryDescriptor(predicate: HKSamplePredicate.workout(predicate))
      .result(for: store)
    try Task.checkCancellation()
    let ownedSources = sources.filter {
      $0.bundleIdentifier == "com.dd.workoutzones.watchkitapp"
        || $0.bundleIdentifier == "com.dd.workoutzones"
    }
    guard !ownedSources.isEmpty else {
      workouts = []
      return
    }
    let owned = NSCompoundPredicate(andPredicateWithSubpredicates: [
      predicate, HKQuery.predicateForObjects(from: Set(ownedSources)),
    ])
    let query = HKSampleQueryDescriptor(
      predicates: [.workout(owned)],
      sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 100)
    let results = try await query.result(for: store)
    try Task.checkCancellation()
    guard generation == request else { return }
    workouts = results.filter {
      $0.sourceRevision.source.bundleIdentifier == "com.dd.workoutzones.watchkitapp"
        || $0.sourceRevision.source.bundleIdentifier == "com.dd.workoutzones"
    }.map { workout in
      let group = workout.zoneGroupsByType?[HKQuantityType(.heartRate)]
      return WorkoutRecord(
        id: workout.uuid, date: workout.startDate, duration: workout.duration,
        zones: group.flatMap { try? ZoneSummary(group: $0, duration: workout.duration) },
        source: group.map { zoneSource($0.configuration.source) } ?? "No zone data")
    }
  }
  enum HistoryError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Health is unavailable on this device." }
  }
}

@main struct WorkoutZonesApp: App {
  @State private var history = WorkoutHistory()
  var body: some Scene { WindowGroup { HistoryView(history: history) } }
}

struct HistoryView: View {
  @Bindable var history: WorkoutHistory
  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "figure.run.circle.fill").font(.system(size: 48)).foregroundStyle(
              .mint)
            Text("Know your effort").font(.title.bold())
            Text(
              "Record an outdoor run on Apple Watch. Review the time spent in your own heart-rate zones here."
            ).foregroundStyle(.secondary)
          }.padding(.vertical, 12)
          if !history.connected {
            Button("Connect to Health", systemImage: "heart.text.clipboard") {
              Task { await history.connect() }
            }.disabled(history.loading)
          }
          NavigationLink("Explore sample workout", value: WorkoutDestination.preview)
        }
        if history.loading { ProgressView("Loading workouts") }
        if history.connected {
          Section("Your runs") {
            if history.workouts.isEmpty {
              ContentUnavailableView(
                "No runs available", systemImage: "figure.run",
                description: Text(
                  "Record with Workout Zones on your watch and allow Health to sync. Health may also return no results when read access is unavailable."
                ))
            }
            ForEach(history.workouts) { record in
              NavigationLink {
                WorkoutDetail(record: record, preview: false)
              } label: {
                VStack(alignment: .leading, spacing: 5) {
                  Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                  Text(
                    Duration.seconds(record.duration).formatted(.time(pattern: .hourMinuteSecond))
                  ).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        Section("About your data") {
          Text(
            "Zone boundaries belong to each workout. A zone number can mean different heart rates on different days."
          )
          Text(
            "Only Workout Zones runs are shown. The app reads Health when you connect or refresh; it stores no separate health database."
          )
        }.font(.footnote).foregroundStyle(.secondary)
      }
      .navigationTitle("Workout Zones")
      .refreshable { await history.refresh() }
      .navigationDestination(for: WorkoutDestination.self) { _ in
        WorkoutDetail(record: .preview, preview: true)
      }
      .alert(
        "Unable to load workouts",
        isPresented: Binding(get: { history.error != nil }, set: { if !$0 { history.error = nil } })
      ) {
        Button("OK") { history.error = nil }
      } message: {
        Text(history.error ?? "")
      }
    }.tint(.teal)
  }
  enum WorkoutDestination: Hashable { case preview }
}

struct WorkoutDetail: View {
  let record: WorkoutRecord
  let preview: Bool
  var body: some View {
    List {
      Section {
        if preview {
          Label("Sample workout · not Health data", systemImage: "info.circle").foregroundStyle(
            .orange)
        }
        Text("Outdoor run").font(.largeTitle.bold())
        Text(record.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(
          .secondary)
        Text(Duration.seconds(record.duration).formatted(.time(pattern: .hourMinuteSecond))).font(
          .system(.title, design: .rounded).bold()
        ).monospacedDigit()
      }
      if let summary = record.zones {
        Section("Time in zones") {
          Chart(summary.bands) { band in
            BarMark(x: .value("Minutes", band.seconds / 60), y: .value("Zone", band.title))
              .foregroundStyle(.teal)
              .accessibilityLabel(band.title)
              .accessibilityValue("\(Int(band.seconds)) seconds, \(band.boundaryLabel)")
          }.frame(height: 220)
          ForEach(summary.bands) { band in
            HStack {
              VStack(alignment: .leading) {
                Text(band.title).font(.headline)
                Text(band.boundaryLabel).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text(Duration.seconds(band.seconds).formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit()
            }
          }
          LabeledContent(
            "Unclassified",
            value: Duration.seconds(summary.unclassifiedSeconds).formatted(
              .time(pattern: .minuteSecond)))
          Text(
            "Unclassified time has no assigned heart-rate zone. It is not added to the lowest zone."
          ).font(.footnote).foregroundStyle(.secondary)
        }
      } else {
        ContentUnavailableView(
          "Zones unavailable", systemImage: "chart.bar",
          description: Text("This workout has no usable heart-rate zone summary."))
      }
      Section {
        Text(record.source)
        Text("These are descriptive workout records, not training prescriptions.").foregroundStyle(
          .secondary)
      }.font(.footnote)
    }.navigationTitle("Run details").navigationBarTitleDisplayMode(.inline)
  }
}
