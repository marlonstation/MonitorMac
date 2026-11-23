import Foundation
import Darwin
import CoreGraphics

struct Sensor: Sendable { let name: String; let celsius: Double }
enum MemoryPressure: String, Sendable {
    case normal = "Normal", warning = "Warning", critical = "Critical"
}

struct Snapshot: Sendable {
    var sensors: [Sensor] = []
    var used: Double? = nil
    var swapUsed: UInt64?
    var memoryPressure: MemoryPressure?
    var total = Double(ProcessInfo.processInfo.physicalMemory)
    var thermal = "—"
    var date = Date()
    var reason = "Waiting for sensors"
    var percent: Double? { used.map { $0 / total * 100 } }
    static func memoryBytes(active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64, purgeable: UInt64, external: UInt64, pageSize: UInt64, total: Double) -> Double {
        let resident = Double(active) + Double(inactive) + Double(wired) + Double(compressed)
        let reclaimable = Double(purgeable) + Double(external)
        return min(total, max(0, resident - reclaimable) * Double(pageSize))
    }
}
final class MetricsReader {
#if EXPERIMENTAL_SENSORS
    static let hasExperimentalSensors = true
#else
    static let hasExperimentalSensors = false
#endif

    func resetSensors() {
#if EXPERIMENTAL_SENSORS
        mm_reset_smc_cache()
#endif
    }
    func read() -> Snapshot {
        var result = Snapshot()
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if status == KERN_SUCCESS {
            result.used = Snapshot.memoryBytes(active: UInt64(vm.active_count), inactive: UInt64(vm.inactive_count), wired: UInt64(vm.wire_count), compressed: UInt64(vm.compressor_page_count), purgeable: UInt64(vm.purgeable_count), external: UInt64(vm.external_page_count), pageSize: UInt64(vm_kernel_page_size), total: result.total)
        }
#if EXPERIMENTAL_SENSORS
        var swap = xsw_usage()
        var swapSize = MemoryLayout.size(ofValue: swap)
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0,
           swapSize == MemoryLayout.size(ofValue: swap) {
            result.swapUsed = swap.xsu_used
        }
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout.size(ofValue: pressure)
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0,
           pressureSize == MemoryLayout.size(ofValue: pressure) {
            switch pressure {
            case 1: result.memoryPressure = .normal
            case 2: result.memoryPressure = .warning
            case 4: result.memoryPressure = .critical
            default: break
            }
        }
#endif
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: result.thermal = "Nominal"
        case .fair: result.thermal = "Fair"
        case .serious: result.thermal = "Serious"
        case .critical: result.thermal = "Critical"
        @unknown default: result.thermal = "Unknown"
        }
#if EXPERIMENTAL_SENSORS
        var buffer = [MMSensor](repeating: MMSensor(), count: 512)
        let hid = buffer.withUnsafeMutableBufferPointer { mm_read_sensors($0.baseAddress, Int32($0.count)) }
        if hid > 0 { result.sensors += buffer.prefix(Int(hid)).map(Self.sensor) }
        let smc = buffer.withUnsafeMutableBufferPointer { mm_read_smc($0.baseAddress, Int32($0.count)) }
        if smc > 0 { result.sensors += buffer.prefix(Int(smc)).map(Self.sensor) }
        let smcDetail = String(cString: mm_smc_message())
        result.reason = result.sensors.isEmpty ? "HID: \(hid). \(smcDetail)" : "\(smcDetail). Automatic Apple Silicon: CPU Tp/Te, GPU Tg; hottest valid sensor per group. Generic PMU sensors are not assigned automatically."
#else
        result.reason = "System thermal state is available. Per-component temperatures are disabled in this build."
#endif
        return result
    }
#if EXPERIMENTAL_SENSORS
    static func sensor(_ raw: MMSensor) -> Sensor {
        var name = raw.name
        let string = withUnsafePointer(to: &name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
        }
        return Sensor(name: string, celsius: raw.celsius)
    }
#endif
}

#if METRICS_TEST
@main struct MetricsTests {
    static func main() {
        precondition(Snapshot.memoryBytes(active: 100, inactive: 50, wired: 20, compressed: 10, purgeable: 5, external: 15, pageSize: 4096, total: 1e9) == 160 * 4096)
        precondition(Snapshot.memoryBytes(active: 0, inactive: 0, wired: 0, compressed: 0, purgeable: 10, external: 10, pageSize: 4096, total: 1e9) == 0)
        precondition(Snapshot.memoryBytes(active: 100, inactive: 0, wired: 0, compressed: 0, purgeable: 0, external: 0, pageSize: 4096, total: 1024) == 1024)
        let sensors = [Sensor(name: "SMC Tp01", celsius: 44), Sensor(name: "SMC Te05", celsius: 46), Sensor(name: "SMC Tg0f", celsius: 42), Sensor(name: "PMU tdie0", celsius: 80), Sensor(name: "SMC TB0T", celsius: 90)]
        precondition(TemperatureSelection.select(sensors, cpu: true)?.celsius == 46)
        precondition(TemperatureSelection.select(sensors, cpu: false)?.celsius == 42)
        precondition(TemperatureSelection.select([], cpu: true) == nil)
        precondition(TemperatureSelection.select([Sensor(name: "SMC Tp01", celsius: .nan)], cpu: true) == nil)
        precondition(TemperatureSelection.select(sensors, cpu: true, key: "ausente") == nil)
        precondition(TemperatureSelection.select(sensors, cpu: true, key: "SMC Tp01")?.celsius == 44)
        var retained = ReadingState()
        let start = Date(timeIntervalSince1970: 100)
        var good = Snapshot(); good.sensors = sensors; good.date = start
        retained.ingest(good, cpuKey: "auto", gpuKey: "auto")
        precondition(retained.ready)
        precondition(!retained.stale(now: start.addingTimeInterval(2), after: 6))
        var failed = Snapshot(); failed.date = start.addingTimeInterval(8)
        retained.ingest(failed, cpuKey: "auto", gpuKey: "auto")
        precondition(retained.cpu?.sensor.celsius == 46 && retained.gpu?.sensor.celsius == 42)
        precondition(retained.stale(now: failed.date, after: 6))
        precondition(retained.cpu?.date == start)
        precondition(!ReadingState().ready)
        good.date = start.addingTimeInterval(9)
        retained.ingest(good, cpuKey: "auto", gpuKey: "auto")
        precondition(!retained.stale(now: good.date, after: 6))
        // A short sleep must invalidate both readings even before normal expiry.
        let wake = good.date.addingTimeInterval(0.1)
        retained.requireFreshReadings(after: wake)
        failed.date = wake.addingTimeInterval(0.1)
        retained.ingest(failed, cpuKey: "auto", gpuKey: "auto")
        precondition(retained.stale(now: failed.date, after: 6))
        precondition(retained.cpu?.sensor.celsius == 46)
        var partial = Snapshot(); partial.date = wake.addingTimeInterval(0.2)
        partial.sensors = [Sensor(name: "SMC Tp01", celsius: 47)]
        retained.ingest(partial, cpuKey: "auto", gpuKey: "auto")
        precondition(!retained.isStale(retained.cpu, now: partial.date, after: 6))
        precondition(retained.isStale(retained.gpu, now: partial.date, after: 6))
        precondition(retained.stale(now: partial.date, after: 6))
        good.date = wake.addingTimeInterval(0.3)
        retained.ingest(good, cpuKey: "auto", gpuKey: "auto")
        precondition(!retained.stale(now: good.date, after: 6))
        // Old rectangular preferences migrate to the compact default, not max.
        precondition(OverlayGeometry.restoredWidth(400, layoutVersion: 0) == 164)
        precondition(OverlayGeometry.restoredWidth(144, layoutVersion: 2) == 144)
        precondition(OverlayGeometry.restoredWidth(.nan, layoutVersion: 2) == 164)
        precondition(OverlayGeometry.width(10) == 144 && OverlayGeometry.width(1000) == 200)
        for width: CGFloat in [144, 164, 184, 200] { precondition(OverlayGeometry.height(width) == width) }
        let original = CGRect(x: 60, y: 80, width: 164, height: 164)
        for (proposed, expected) in [(CGFloat(-900), CGFloat(144)), (151, 151), (900, 200)] {
            let resized = OverlayGeometry.resizedFrame(from: original, proposedSide: proposed)
            precondition(resized.size == CGSize(width: expected, height: expected))
            precondition(resized.minX == original.minX && resized.maxY == original.maxY)
        }
        let secondaryDisplay = CGRect(x: -1280, y: 40, width: 1280, height: 900)
        precondition(OverlayCorner.topRight.origin(in: secondaryDisplay, side: 164, margin: 16) == CGPoint(x: -180, y: 760))
        precondition(OverlayCorner.bottomLeft.origin(in: secondaryDisplay, side: 144, margin: 32) == CGPoint(x: -1248, y: 72))
        let sample = MetricsReader().read()
        precondition(sample.used != nil && sample.used! > 0 && sample.used! <= sample.total)
        print("PASS: sensor selection, reading expiry, wake handling, square layout, and real memory sampling. Estimated RAM: \(sample.used! / 1073741824) GiB. \(sample.reason)")
        for s in sample.sensors { print("\(s.name): \(s.celsius) °C") }
    }
}
#endif
