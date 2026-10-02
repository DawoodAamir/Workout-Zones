import HealthKit

extension ZoneSummary {
  init(group: HKWorkoutZoneGroup, duration: TimeInterval) throws {
    let unit = HKUnit.count().unitDivided(by: .minute())
    let bands = group.configuration.zones.map { zone in
      ZoneBand(
        index: zone.index, minimum: zone.minimum?.doubleValue(for: unit),
        maximum: zone.maximum?.doubleValue(for: unit),
        seconds: group.zoneDurations.first(where: { $0.zone.index == zone.index })?.duration ?? 0)
    }
    try self.init(bands: bands, workoutSeconds: duration)
  }
}

func zoneSource(_ source: HKWorkoutZoneConfiguration.Source) -> String {
  switch source {
  case .system: "HealthKit automatic zones"
  case .user: "Your configured zones"
  case .app: "App-defined zones"
  @unknown default: "HealthKit zones"
  }
}
