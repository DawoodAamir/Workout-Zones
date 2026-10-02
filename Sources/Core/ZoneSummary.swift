import Foundation

/// A display snapshot preserves each workout's actual boundaries; zone numbers alone are not comparable.
struct ZoneBand: Sendable, Equatable, Identifiable {
  let index: Int
  let minimum: Double?
  let maximum: Double?
  let seconds: TimeInterval
  var id: Int { index }
  var title: String { "Zone \(index + 1)" }
  var boundaryLabel: String {
    switch (minimum, maximum) {
    case (let low?, let high?): "\(Int(low.rounded()))–<\(Int(high.rounded())) bpm"
    case (let low?, nil): "≥\(Int(low.rounded())) bpm"
    case (nil, let high?): "<\(Int(high.rounded())) bpm"
    default: "No boundaries"
    }
  }
}

struct ZoneSummary: Sendable, Equatable {
  let bands: [ZoneBand]
  let workoutSeconds: TimeInterval
  var measuredSeconds: TimeInterval { bands.reduce(0) { $0 + $1.seconds } }
  var unclassifiedSeconds: TimeInterval { max(0, workoutSeconds - measuredSeconds) }

  init(bands: [ZoneBand], workoutSeconds: TimeInterval) throws {
    guard workoutSeconds.isFinite, workoutSeconds >= 0, workoutSeconds <= 172_800,
      bands.count <= 9, Set(bands.map(\.index)).count == bands.count
    else { throw Validation.invalid }
    for (offset, band) in bands.enumerated() {
      guard band.index == offset, band.seconds.isFinite, band.seconds >= 0,
        band.seconds <= workoutSeconds + 1
      else { throw Validation.invalid }
      for value in [band.minimum, band.maximum].compactMap({ $0 }) {
        guard value.isFinite, value > 0, value < 500 else { throw Validation.invalid }
      }
      if let low = band.minimum, let high = band.maximum, low >= high { throw Validation.invalid }
      if offset > 0 {
        guard let previous = bands[offset - 1].maximum, band.minimum == previous else {
          throw Validation.invalid
        }
      }
    }
    guard bands.reduce(0, { $0 + $1.seconds }) <= workoutSeconds + 1 else {
      throw Validation.invalid
    }
    self.bands = bands
    self.workoutSeconds = workoutSeconds
  }
  enum Validation: Error { case invalid }

  static let preview: ZoneSummary = {
    let boundaries: [Double?] = [nil, 115, 135, 150, 165, nil]
    let durations: [Double] = [120, 300, 900, 360, 60]
    return try! ZoneSummary(
      bands: durations.enumerated().map { index, duration in
        ZoneBand(
          index: index, minimum: boundaries[index], maximum: boundaries[index + 1],
          seconds: duration)
      }, workoutSeconds: 1_800)
  }()
}

/// Suppresses repeated zone cues and late callbacks after pause or workout replacement.
struct ZoneCueGate: Sendable {
  private var lastZone: Int?
  private var lastCue: Date?
  mutating func reset() {
    lastZone = nil
    lastCue = nil
  }
  mutating func shouldCue(zone: Int, sampleDate: Date?, now: Date, running: Bool) -> Bool {
    guard running, zone >= 0, zone < 9, let sampleDate,
      now.timeIntervalSince(sampleDate) >= -2,
      now.timeIntervalSince(sampleDate) <= 15
    else { return false }
    defer { lastZone = zone }
    guard let previous = lastZone, previous != zone else { return false }
    guard lastCue.map({ now.timeIntervalSince($0) >= 10 }) ?? true else { return false }
    lastCue = now
    return true
  }
}
