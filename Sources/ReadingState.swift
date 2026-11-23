import Foundation

struct TemperatureReading {
    let sensor: Sensor
    let date: Date
}
struct ReadingState {
    var cpu: TemperatureReading?
    var gpu: TemperatureReading?
    private var requiredAfter: Date?
    mutating func requireFreshReadings(after date: Date) { requiredAfter = date }
    mutating func ingest(_ snapshot: Snapshot, cpuKey: String, gpuKey: String) {
        if let sensor = TemperatureSelection.select(snapshot.sensors, cpu: true, key: cpuKey) { cpu = TemperatureReading(sensor: sensor, date: snapshot.date) }
        if let sensor = TemperatureSelection.select(snapshot.sensors, cpu: false, key: gpuKey) { gpu = TemperatureReading(sensor: sensor, date: snapshot.date) }
    }
    var ready: Bool { cpu != nil && gpu != nil }
    func isStale(_ reading: TemperatureReading?, now: Date, after seconds: Double) -> Bool {
        guard let reading else { return true }
        if let requiredAfter, reading.date <= requiredAfter { return true }
        return now.timeIntervalSince(reading.date) > seconds
    }
    func stale(now: Date, after seconds: Double) -> Bool {
        isStale(cpu, now: now, after: seconds) || isStale(gpu, now: now, after: seconds)
    }
}
