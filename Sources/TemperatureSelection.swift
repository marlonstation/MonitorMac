import Foundation

// Use the highest valid temperature in the selected SMC group.
// Tp and Te identify CPU sensors, while Tg identifies GPU sensors.
enum TemperatureSelection {
    static func select(_ sensors: [Sensor], cpu: Bool, key: String = "auto") -> Sensor? {
        let valid = sensors.filter { $0.celsius.isFinite && $0.celsius > 0 && $0.celsius < 150 }
        if key != "auto" { return valid.first { $0.name == key } }
        return valid.filter { sensor in
            if sensor.name.hasPrefix("SMC ") {
                let name = String(sensor.name.dropFirst(4))
                guard name.utf8.count == 4 else { return false }
                return cpu ? (name.hasPrefix("Tp") || name.hasPrefix("Te")) : name.hasPrefix("Tg")
            }
            let name = sensor.name.lowercased()
            return cpu ? (name.hasPrefix("pacc mtr temp") || name.hasPrefix("eacc mtr temp") || name.contains("cpu temperature")) : (name.hasPrefix("gpu mtr temp") || name.contains("gpu temperature"))
        }.max { $0.celsius < $1.celsius }
    }
}
