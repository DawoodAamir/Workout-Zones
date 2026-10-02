import HealthKit
import Observation
import WatchKit

@MainActor @Observable final class WorkoutRecorder: NSObject {
  enum Phase { case ready, preparing, running, paused, saving, saved }
  private(set) var phase: Phase = .ready
  private(set) var heartRate: Double?
  private(set) var sampleDate: Date?
  private(set) var currentZone: Int?
  private(set) var summary: ZoneSummary?
  private(set) var source = "Zones appear when HealthKit supplies a configuration."
  private(set) var elapsed: TimeInterval = 0
  var error: String?
  var haptics = false
  var preview = false
  private let healthStore = HKHealthStore()
  private var session: HKWorkoutSession?
  private var builder: HKLiveWorkoutBuilder?
  private var cueGate = ZoneCueGate()
  private var timer: Task<Void, Never>?
  private var saveOnEnd = true
  private var ending = false
  private let heartType = HKQuantityType(.heartRate)

  func start() async {
    guard phase == .ready || phase == .saved else { return }
    guard HKHealthStore.isHealthDataAvailable() else {
      error = "HealthKit is unavailable on this device."
      return
    }
    phase = .preparing
    preview = false
    heartRate = nil
    sampleDate = nil
    currentZone = nil
    summary = nil
    elapsed = 0
    cueGate.reset()
    ending = false
    do {
      try await healthStore.requestAuthorization(
        toShare: [HKObjectType.workoutType()], read: [HKObjectType.workoutType(), heartType])
      guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
      else {
        throw RecorderError.permission
      }
      let configuration = HKWorkoutConfiguration()
      configuration.activityType = .running
      configuration.locationType = .outdoor
      let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
      let newBuilder = newSession.associatedWorkoutBuilder()
      session = newSession
      builder = newBuilder
      newSession.delegate = self
      newBuilder.delegate = self
      newBuilder.dataSource = HKLiveWorkoutDataSource(
        healthStore: healthStore, workoutConfiguration: configuration)
      let start = Date()
      newSession.startActivity(with: start)
      try await newBuilder.beginCollection(at: start)
      guard session === newSession else { return }
      if let zones = try await newBuilder.zoneConfiguration(for: heartType) {
        source = zoneSource(zones.source)
      } else {
        source = "No heart-rate zones available. Configure workout zones in Health settings."
      }
      guard session === newSession, phase == .preparing else { return }
      phase = .running
      beginClock()
    } catch {
      session?.end()
      builder?.discardWorkout()
      clearSession()
      phase = .ready
      self.error = error.localizedDescription
    }
  }
  func startPreview() {
    guard phase == .ready || phase == .saved else { return }
    preview = true
    phase = .running
    elapsed = 1_800
    heartRate = 142
    sampleDate = Date()
    currentZone = 2
    summary = .preview
    source = "Sample boundaries · no Health data is read or saved"
  }
  func pauseOrResume() {
    guard phase == .running || phase == .paused else { return }
    if preview {
      phase = phase == .running ? .paused : .running
      return
    }
    if phase == .running { session?.pause() } else { session?.resume() }
    cueGate.reset()
  }
  func finish(save: Bool) {
    guard phase == .running || phase == .paused, !ending else { return }
    if preview {
      phase = .ready
      preview = false
      return
    }
    ending = true
    saveOnEnd = save
    phase = .saving
    timer?.cancel()
    session?.end()
  }
  func reset() {
    guard phase == .saved else { return }
    phase = .ready
  }
  private func beginClock() {
    timer?.cancel()
    timer = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        if let builder = self.builder { self.elapsed = builder.elapsedTime }
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
      }
    }
  }
  private func complete(_ completedSession: HKWorkoutSession, at date: Date) async {
    guard session === completedSession, let builder else { return }
    phase = .saving
    timer?.cancel()
    do {
      try await builder.endCollection(at: date)
      guard session === completedSession else { return }
      if saveOnEnd {
        _ = try await builder.finishWorkout()
        phase = .saved
      } else {
        builder.discardWorkout()
        phase = .ready
      }
      clearSession()
    } catch {
      builder.discardWorkout()
      clearSession()
      phase = .ready
      self.error = "The workout could not be saved. \(error.localizedDescription)"
    }
  }
  private func clearSession() {
    timer?.cancel()
    timer = nil
    session?.delegate = nil
    builder?.delegate = nil
    session = nil
    builder = nil
    ending = false
  }
  private func receive(_ update: HKLiveWorkoutZoneUpdate, from sourceBuilder: HKLiveWorkoutBuilder)
  {
    guard builder === sourceBuilder, phase == .running || phase == .paused else { return }
    currentZone = update.currentZoneDuration?.zone.index
    if let group = update.zoneGroup {
      summary = try? ZoneSummary(group: group, duration: sourceBuilder.elapsedTime)
      source = zoneSource(group.configuration.source)
    }
    if let zone = currentZone,
      cueGate.shouldCue(
        zone: zone, sampleDate: update.lastSampleProcessedDate, now: Date(),
        running: phase == .running), haptics
    {
      WKInterfaceDevice.current().play(.directionUp)
    }
  }
  enum RecorderError: LocalizedError {
    case permission
    var errorDescription: String? {
      "Allow Workout Zones to save workouts in Health before starting."
    }
  }
}

extension WorkoutRecorder: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState, date: Date
  ) {
    Task { @MainActor [weak self] in
      guard let self, self.session === workoutSession else { return }
      switch toState {
      case .running: if !self.ending, self.phase == .paused { self.phase = .running }
      case .paused: if !self.ending { self.phase = .paused }
      case .ended: await self.complete(workoutSession, at: date)
      default: break
      }
    }
  }
  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error)
  {
    Task { @MainActor [weak self] in
      guard let self, self.session === workoutSession else { return }
      self.builder?.discardWorkout()
      self.clearSession()
      self.phase = .ready
      self.error = error.localizedDescription
    }
  }
  nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
  nonisolated func workoutBuilder(
    _ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>
  ) {
    let type = HKQuantityType(.heartRate)
    guard collectedTypes.contains(type), let stats = workoutBuilder.statistics(for: type),
      let value = stats.mostRecentQuantity()?.doubleValue(
        for: HKUnit.count().unitDivided(by: .minute()))
    else { return }
    let date = stats.mostRecentQuantityDateInterval()?.end
    Task { @MainActor [weak self] in
      guard let self, self.builder === workoutBuilder else { return }
      self.heartRate = value
      self.sampleDate = date
    }
  }
  nonisolated func workoutBuilder(
    _ workoutBuilder: HKLiveWorkoutBuilder, didUpdateWorkoutZone zoneUpdate: HKLiveWorkoutZoneUpdate
  ) {
    Task { @MainActor [weak self] in self?.receive(zoneUpdate, from: workoutBuilder) }
  }
}
