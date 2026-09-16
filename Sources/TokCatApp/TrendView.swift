import SwiftUI
import Charts
import TokCatCore
import TokCatEngine

/// 趋势图上的一个数据点。
struct TrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// 菜单内嵌图表的一份**不可变快照**。
///
/// 打开菜单时生成一次，菜单打开期间不再实时重绘，避免每秒重算坐标域导致的抖动。
struct TrendChartData: Equatable {
    struct Series: Identifiable, Equatable {
        let id: String
        let name: String
        let color: Color
        let points: [TrendPoint]
        let subtotal: Double
    }

    var series: [Series] = []
    var rate: Double = 0
    var total: Double = 0
    var peak: Double = 0
    var currency: Bool = false
    var metricName: String = ""
    /// 冻结的 Y 轴上限（“好看”的整数刻度）。
    var yMax: Double = 1

    static let empty = TrendChartData()

    /// 固定的趋势范围（分钟）。
    static let rangeMinutes = 5
}

/// 把 `RateEngine` 快照转成图表数据的视图模型。
///
/// 不做实时发布：菜单打开时调用 `chartData()` 取一次快照即可。
final class TrendModel {
    private var trend: RateHistory.RateTrend?
    private var sourceNames: [String: String] = [:]
    private var rate: Double = 0
    private var currency: Bool = false
    private var metricName: String = ""

    /// 图表每条线的目标最大点数（统计仍按 1 秒，不受影响）。
    private let chartPointBudget = 120
    /// 图例最多展示的客户端数，保证菜单高度稳定。
    private let maxLegendSeries = 4
    /// 折线平滑窗口（秒）。仅影响显示，`合计/峰值` 仍用原始值。
    private let smoothingSeconds = 15

    /// 立即更新口径名称（菜单下次打开时生效）。
    func setMetricName(_ name: String) {
        metricName = name
    }

    func update(from snapshot: RateSnapshot, metricName: String) {
        trend = snapshot.trend
        sourceNames = snapshot.sourceNames
        rate = snapshot.rate
        currency = snapshot.unitIsCurrency
        self.metricName = metricName
    }

    /// 生成当前时刻的图表快照。
    func chartData() -> TrendChartData {
        var data = TrendChartData()
        data.rate = rate
        data.currency = currency
        data.metricName = metricName

        guard let trend, !trend.timestamps.isEmpty else { return data }

        let rangeSeconds = TrendChartData.rangeMinutes * 60
        let count = trend.timestamps.count
        let startIndex = max(0, count - rangeSeconds)

        let windowed = trend.total[startIndex...]
        data.total = windowed.reduce(0, +)
        data.peak = windowed.max() ?? 0

        // 最近 1 秒：取最近一个**完整**秒（倒数第二个桶），避免显示进行中的半截秒。
        let completedIndex = max(startIndex, count - 2)
        if completedIndex < count {
            data.rate = trend.total[completedIndex]
        }

        // 降采样：把相邻若干秒合成一个点。
        let step = max(1, Int((Double(rangeSeconds) / Double(chartPointBudget)).rounded()))

        var result: [TrendChartData.Series] = []
        for (sourceId, values) in trend.perSource {
            guard values.count == count else { continue }
            let slice = Array(values[startIndex...])
            let subtotal = slice.reduce(0, +)
            guard subtotal > 0 else { continue }

            var points: [TrendPoint] = []
            var index = 0
            while index < slice.count {
                let end = min(index + step, slice.count)
                let span = max(1, end - index)
                let sum = slice[index..<end].reduce(0, +)
                points.append(TrendPoint(
                    date: trend.timestamps[startIndex + end - 1],
                    value: sum / Double(span)
                ))
                index = end
            }

            // 对显示值做居中滑动平均，抹平突发流量的尖刺（统计不受影响）。
            let window = max(1, Int((Double(smoothingSeconds) / Double(step)).rounded()))
            let smoothed = TrendMath.movingAverage(points.map(\.value), window: window)
            points = zip(points, smoothed).map { TrendPoint(date: $0.date, value: $1) }

            result.append(TrendChartData.Series(
                id: sourceId,
                name: sourceNames[sourceId] ?? sourceId,
                color: SourcePalette.color(for: sourceId),
                points: points,
                subtotal: subtotal
            ))
        }

        result.sort { $0.subtotal > $1.subtotal }
        data.series = Array(result.prefix(maxLegendSeries))
        let linePeak = data.series.flatMap { $0.points.map(\.value) }.max() ?? 0
        data.yMax = TrendMath.niceMax(max(linePeak, data.peak))
        return data
    }
}

/// 菜单内嵌的紧凑趋势图（每个客户端一条彩色折线）。
struct TrendChartView: View {
    let data: TrendChartData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("消耗趋势 · 最近 \(TrendChartData.rangeMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(data.metricName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            stats

            chart

            if !data.series.isEmpty {
                legend
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 340)
    }

    private var stats: some View {
        HStack(spacing: 16) {
            stat("最近 1 秒", Formatting.rate(data.rate, currency: data.currency))
            stat("合计", Formatting.units(data.total, currency: data.currency))
            stat("单秒峰值", Formatting.rate(data.peak, currency: data.currency))
            Spacer(minLength: 0)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .rounded))
                .monospacedDigit()
        }
    }

    private var chart: some View {
        Chart {
            ForEach(data.series) { series in
                ForEach(series.points) { point in
                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value("消耗", point.value),
                        series: .value("客户端", series.name)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [series.color.opacity(0.18), series.color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("消耗", point.value),
                        series: .value("客户端", series.name)
                    )
                    .foregroundStyle(series.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...data.yMax)
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
            ForEach(data.series) { series in
                HStack(spacing: 5) {
                    Circle()
                        .fill(series.color)
                        .frame(width: 7, height: 7)
                    Text(series.name)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Formatting.units(series.subtotal, currency: data.currency))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
