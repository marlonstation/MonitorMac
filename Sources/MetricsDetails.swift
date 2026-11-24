import SwiftUI

struct HistorySample {
    let date: Date
    let cpu: Double?
    let gpu: Double?
    let ram: Double?
}

final class MetricsHistory: ObservableObject {
    static let duration: TimeInterval = 600
    @Published private(set) var samples: [HistorySample] = []

    func append(_ sample: HistorySample) {
        // A clock change backwards would otherwise leave future samples on the chart.
        if let last = samples.last, last.date > sample.date { samples.removeAll() }
        let cutoff = sample.date.addingTimeInterval(-Self.duration)
        samples.removeAll { $0.date < cutoff }
        if samples.count >= 600 { samples.removeFirst() }
        samples.append(sample)
    }
}

struct MetricsDetails: View {
    @ObservedObject var model: Model
    @ObservedObject var history: MetricsHistory
    private var themed: Bool { model.theme.isGTA6 }
    private var cpuColor: Color { themed ? Color(nsColor: model.theme.accent) : .orange }
    private var gpuColor: Color { themed ? model.theme.lavender : .blue }
    private var ramColor: Color { themed ? model.theme.rose : .purple }
    private var labelColor: Color { themed ? Color(nsColor: model.theme.text).opacity(0.78) : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 20) {
                detail("RAM used (estimate)", model.memoryText)
                Spacer()
                detail("Memory pressure", model.snapshot.memoryPressure?.rawValue ?? "Unavailable")
                if MetricsReader.hasExperimentalSensors {
                    Spacer()
                    detail("Swap used", model.snapshot.swapUsed.map(swapText) ?? "Unavailable")
                } else {
                    Spacer()
                    detail("Thermal state", model.snapshot.thermal)
                }
            }

            if MetricsReader.hasExperimentalSensors {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperatures").font(.headline)
                        Spacer()
                        legend("CPU", color: cpuColor)
                        legend("GPU", color: gpuColor)
                    }
                    let temperatures = history.samples.flatMap { [$0.cpu, $0.gpu].compactMap { $0 } }
                    let lower = max(0, floor(((temperatures.min() ?? 30) - 2) / 10) * 10)
                    let upper = max(lower + 10, ceil(((temperatures.max() ?? 60) + 2) / 10) * 10)
                    plot(domain: lower...upper, unit: "°C", series: [(\.cpu, cpuColor), (\.gpu, gpuColor)])
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("RAM usage").font(.headline)
                plot(domain: 0...100, unit: "%", series: [(\.ram, ramColor)])
                HStack {
                    Text("10 minutes ago")
                    Spacer()
                    Text("Latest sample")
                }.font(.caption).foregroundStyle(labelColor)
            }

            Text("History is kept in memory while MonitorMac is running.")
                .font(.caption).foregroundStyle(labelColor)
        }
        .padding(24)
        .frame(width: 495, height: 425)
        .foregroundStyle(themed ? Color(nsColor: model.theme.text) : .primary)
        .background(themed ? model.theme.surface : AnyShapeStyle(Color.clear))
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(labelColor)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private func swapText(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        let locale = Locale(identifier: "en_US_POSIX")
        if mib < 1024 { return String(format: "%.0f MiB", locale: locale, mib) }
        return String(format: "%.1f GiB", locale: locale, mib / 1024)
    }

    private func legend(_ title: String, color: Color) -> some View {
        Label(title, systemImage: "circle.fill")
            .font(.caption)
            .foregroundStyle(color)
    }

    private func plot(domain: ClosedRange<Double>, unit: String,
                      series: [(KeyPath<HistorySample, Double?>, Color)]) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing) {
                Text("\(Int(domain.upperBound))\(unit)")
                Spacer()
                Text("\(Int(domain.lowerBound))\(unit)")
            }.font(.caption2.monospacedDigit()).foregroundStyle(labelColor)
            Canvas { context, size in
                guard let end = history.samples.last?.date else { return }
                let start = end.addingTimeInterval(-MetricsHistory.duration)
                let span = domain.upperBound - domain.lowerBound
                var guides = Path()
                for fraction in [0.25, 0.5, 0.75] {
                    let y = size.height * fraction
                    guides.move(to: CGPoint(x: 0, y: y))
                    guides.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(guides, with: .color(labelColor.opacity(0.2)), lineWidth: 1)
                for (key, color) in series {
                    var path = Path()
                    var previous: Date?
                    var latest: CGPoint?
                    for sample in history.samples {
                        guard let value = sample[keyPath: key] else {
                            previous = nil
                            latest = nil
                            continue
                        }
                        let x = sample.date.timeIntervalSince(start) / MetricsHistory.duration
                        let y = (value - domain.lowerBound) / span
                        let point = CGPoint(x: 3 + x * (size.width - 6), y: 3 + (1 - y) * (size.height - 6))
                        if let previous, sample.date.timeIntervalSince(previous) <= 12 {
                            path.addLine(to: point)
                        } else {
                            path.move(to: point)
                        }
                        previous = sample.date
                        latest = point
                    }
                    context.stroke(path, with: .color(color), lineWidth: 2)
                    if let latest {
                        context.fill(Path(ellipseIn: CGRect(x: latest.x - 2, y: latest.y - 2, width: 4, height: 4)),
                                     with: .color(color))
                    }
                }
            }
            .background(themed ? Color.black.opacity(0.23) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8))
        }.frame(height: 90)
    }
}
