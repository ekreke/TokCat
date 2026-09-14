import SwiftUI
import Charts
import TokCatCore

/// 趋势图上的一个数据点。
struct TrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// 趋势弹窗的视图模型，由 `RateEngine` 的主线程快照驱动。
final class TrendModel: ObservableObject {
    /// 可选的时间范围（分钟）。
    static let rangeOptions = [1, 5, 10]

    /// 每个客户端的序列（含范围内小计，用于图例）。
    struct Series: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [TrendPoint]
        let subtotal: Double
    }

    @Published var series: [Series] = []
    @Published var rate: Double = 0
    @Published var total: Double = 0
    @Published var peak: Double = 0
    @Published var currency: Bool = false
    @Published var metricName: String = ""

    /// 当前筛选的时间范围（分钟）。
    @Published var rangeMinutes: Int = 5 {
        didSet {
            guard rangeMinutes != oldValue else { return }
            onRangeChange?(rangeMinutes)
            recompute()
        }
    }

    /// 范围变化回调，用于持久化。
    var onRangeChange: ((Int) -> Void)?

    private var trend: RateHistory.RateTrend?
    private var sourceNames: [String: String] = [:]

    /// 图表每条线的目标最大点数（统计仍按 1 秒，不受影响）。
    private let chartPointBudget = 120

    func update(from snapshot: RateSnapshot, metricName: String) {
        trend = snapshot.trend
        sourceNames = snapshot.sourceNames
        rate = snapshot.rate
        currency = snapshot.unitIsCurrency
        self.metricName = metricName
        recompute()
    }

    private func recompute() {
        guard let trend, !trend.timestamps.isEmpty else {
            series = []
            total = 0
            peak = 0
            return
        }

        let rangeSeconds = rangeMinutes * 60
        let count = trend.timestamps.count
        let startIndex = max(0, count - rangeSeconds)

        // 统计按 1 秒粒度（峰值 = 最高 1 秒消耗）
        total = trend.total[startIndex...].reduce(0, +)
        peak = trend.total[startIndex...].max() ?? 0

        // 图表降采样：把相邻若干秒合成一个点
        let step = max(1, Int((Double(rangeSeconds) / Double(chartPointBudget)).rounded()))

        var result: [Series] = []
        for (sourceId, values) in trend.perSource {
            guard values.count == count else { continue }
            let slice = Array(values[startIndex...])
            let subtotal = slice.reduce(0, +)
            guard subtotal > 0 else { continue }

            var points: [TrendPoint] = []
            var index = 0
            while index < slice.count {
                let end = min(index + step, slice.count)
                let sum = slice[index..<end].reduce(0, +)
                points.append(TrendPoint(
                    date: trend.timestamps[startIndex + end - 1],
                    value: sum
                ))
                index = end
            }

            result.append(Series(
                id: sourceId,
                name: sourceNames[sourceId] ?? sourceId,
                color: SourcePalette.color(for: sourceId),
                points: points,
                subtotal: subtotal
            ))
        }

        result.sort { $0.subtotal > $1.subtotal }
        series = result
    }
}

/// 菜单内嵌的紧凑趋势图（每个客户端一条彩色折线）。
///
/// 范围切换由外层菜单项负责，这里只负责画图与图例，避免在 NSMenu 里
/// 放置可点击的分段控件。
struct TrendChartView: View {
    @ObservedObject var model: TrendModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("消耗趋势 · 最近 \(model.rangeMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.metricName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            chart

            if !model.series.isEmpty {
                legend
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 340)
    }

    private var chart: some View {
        Chart {
            ForEach(model.series) { series in
                ForEach(series.points) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("消耗", point.value),
                        series: .value("客户端", series.name)
                    )
                    .foregroundStyle(series.color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Formatting.compact(number))
                    }
                }
            }
        }
        .frame(height: 110)
    }

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(model.series) { series in
                HStack(spacing: 5) {
                    Circle()
                        .fill(series.color)
                        .frame(width: 7, height: 7)
                    Text(series.name)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Formatting.units(series.subtotal, currency: model.currency))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
