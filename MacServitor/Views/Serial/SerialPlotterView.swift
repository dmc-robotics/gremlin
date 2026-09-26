import Charts
import ServitorKit
import SwiftUI

/// One line per data key, plotted against seconds since the oldest buffered sample.
struct SerialPlotterView: View {
    @Environment(SerialModel.self) private var serial

    var body: some View {
        if serial.buffer.hasPlotData {
            Chart(PlotPoint.points(from: serial.buffer)) { point in
                LineMark(
                    x: .value("Elapsed time (s)", point.elapsed),
                    y: .value("Value", point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(by: .value("Series", point.series))
            }
            .chartXAxisLabel("Elapsed time (s)")
            .chartYAxisLabel("Value")
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXScale(domain: .automatic(includesZero: false))
            .padding()
        } else {
            ContentUnavailableView(
                "No Data to Plot",
                systemImage: "chart.xyaxis.line",
                description: Text("Send numeric data such as temp:25 or x:10,y:20,z:30")
            )
        }
    }
}

struct PlotPoint: Identifiable, Equatable {
    /// Index of the sample in the buffer; unique within a series even if timestamps repeat
    let sample: Int
    let series: String
    /// Unique per unbroken run of a series; a missing sample starts a new segment so
    /// the line has a gap instead of bridging it.
    let segment: String
    let elapsed: Double
    let value: Double

    var id: String { "\(series)#\(sample)" }

    static func points(from buffer: SerialBuffer) -> [PlotPoint] {
        guard let start = buffer.timestamps.first else { return [] }
        let elapsed = buffer.timestamps.map { $0.timeIntervalSince(start) }

        var points: [PlotPoint] = []
        for name in buffer.seriesNames {
            var segmentIndex = 0
            for (index, value) in (buffer.seriesValues[name] ?? []).enumerated() {
                guard let value else {
                    segmentIndex += 1
                    continue
                }
                points.append(PlotPoint(
                    sample: index,
                    series: name,
                    segment: "\(name)#\(segmentIndex)",
                    elapsed: elapsed[index],
                    value: value
                ))
            }
        }
        return points
    }
}
