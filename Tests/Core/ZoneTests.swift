import Foundation
import Testing

@testable import WorkoutZonesCore

@Test func summaryPreservesBoundariesAndMissingTime() throws {
  let summary = try ZoneSummary(
    bands: [
      ZoneBand(index: 0, minimum: nil, maximum: 120, seconds: 60),
      ZoneBand(index: 1, minimum: 120, maximum: nil, seconds: 90),
    ], workoutSeconds: 180)
  #expect(summary.measuredSeconds == 150)
  #expect(summary.unclassifiedSeconds == 30)
  #expect(summary.bands[0].boundaryLabel == "<120 bpm")
  #expect(summary.bands[1].boundaryLabel == "≥120 bpm")
  #expect(ZoneSummary.preview.measuredSeconds == 1740)
}

@Test func rejectsNonFiniteOverlappingAndExcessDurations() {
  let invalid: [[ZoneBand]] = [
    [.init(index: 0, minimum: nil, maximum: .nan, seconds: 10)],
    [
      .init(index: 0, minimum: nil, maximum: 120, seconds: 70),
      .init(index: 1, minimum: 115, maximum: nil, seconds: 10),
    ],
    [
      .init(index: 0, minimum: nil, maximum: 120, seconds: 70),
      .init(index: 1, minimum: 120, maximum: nil, seconds: 40),
    ],
    [.init(index: 0, minimum: nil, maximum: nil, seconds: -.infinity)],
  ]
  for bands in invalid {
    #expect(throws: ZoneSummary.Validation.self) {
      try ZoneSummary(bands: bands, workoutSeconds: 100)
    }
  }
}

@Test func cuesIgnoreInitialStalePausedAndRapidUpdates() {
  var gate = ZoneCueGate()
  let date = Date(timeIntervalSince1970: 1000)
  let cue1 = !gate.shouldCue(zone: 1, sampleDate: date, now: date, running: true)
  #expect(cue1)
  let cue2 = gate.shouldCue(zone: 2, sampleDate: date, now: date, running: true)
  #expect(cue2)
  let cue3 = !gate.shouldCue(
    zone: 3, sampleDate: date, now: date.addingTimeInterval(1), running: true)
  #expect(cue3)
  let cue4 = !gate.shouldCue(
    zone: 4, sampleDate: date, now: date.addingTimeInterval(20), running: true)
  #expect(cue4)
  let cue5 = !gate.shouldCue(zone: 4, sampleDate: date, now: date, running: false)
  #expect(cue5)
  let cue6 = gate.shouldCue(
    zone: 4, sampleDate: date.addingTimeInterval(12), now: date.addingTimeInterval(12),
    running: true)
  #expect(cue6)
  gate.reset()
  let cue7 = !gate.shouldCue(zone: 2, sampleDate: date, now: date, running: true)
  #expect(cue7)
}
