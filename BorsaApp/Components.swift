import SwiftUI
import Charts

enum Palette {
    static let accent = Color("AccentColor")
    static let background = Color("Background")
    static let surface = Color("Surface")
    static let raised = Color("Raised")
    static let line = Color("Line")
    static let positive = Color("PositiveColor")
    static let negative = Color("NegativeColor")
    static let onAccent = Color("OnAccent")
}

struct DataBadge: View {
    var body: some View {
        Label("Örnek veri", systemImage: "circle.dotted")
            .labelStyle(.titleAndIcon).fixedSize(horizontal: true, vertical: false)
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Palette.raised, in: Capsule())
            .accessibilityLabel("Örnek piyasa verisi. Canlı bağlantı yok.")
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}

struct StockBadge: View {
    let symbol: String
    var body: some View {
        Text(String(symbol.prefix(2)))
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .frame(width: 44, height: 44)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct ChangeLabel: View {
    let percent: Double
    var body: some View {
        Label(String(format: "%+.2f%%", percent).replacingOccurrences(of: ".", with: ","),
              systemImage: percent >= 0 ? "arrow.up.right" : "arrow.down.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(percent >= 0 ? Palette.positive : Palette.negative)
            .monospacedDigit()
    }
}

struct PriceChart: View {
    let instrument: Instrument
    var days = 1
    var compact = false
    @State private var selectedIndex: Int?
    private var values: [Double] { DemoMarket.history(for: instrument, days: days) }
    private var color: Color { instrument.changePercent >= 0 ? Palette.accent : Palette.negative }
    private var range: ClosedRange<Double> {
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max((high - low) * 0.2, 0.1)
        return (low - padding)...(high + padding)
    }
    private var selectedPrice: String {
        guard let index = selectedIndex, values.indices.contains(index) else { return "Temsili fiyat grafiği" }
        return "Örnek fiyat · \(Money.formatted(Int64((values[index] * 100).rounded())))"
    }

    var body: some View {
        if compact {
            Sparkline(values: values).stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(height: 30).allowsHitTesting(false).accessibilityHidden(true)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(selectedPrice).font(.caption).monospacedDigit()
                    Spacer(minLength: 2)
                    Text("TL").font(.caption)
                }.foregroundStyle(.secondary)
                Chart(Array(values.enumerated()), id: \.offset) { item in
                    AreaMark(x: .value("Örnek nokta", item.offset), yStart: .value("Taban", range.lowerBound), yEnd: .value("Fiyat", item.element))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.18), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Örnek nokta", item.offset), y: .value("Fiyat", item.element))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                    if let index = selectedIndex, index == item.offset {
                        RuleMark(x: .value("Seçim", index)).foregroundStyle(Palette.line)
                        PointMark(x: .value("Seçim", index), y: .value("Fiyat", values[index])).foregroundStyle(color)
                    }
                }
                .chartYScale(domain: range)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(Palette.line.opacity(0.6))
                        AxisValueLabel().foregroundStyle(Color.secondary)
                    }
                }
                .chartXSelection(value: $selectedIndex)
                .frame(height: 155)
                .accessibilityLabel("\(instrument.symbol) temsili fiyat grafiği. Gerçek geçmiş fiyat değildir.")
                HStack { Text("Başlangıç"); Spacer(); Text("Örnek seans"); Spacer(); Text("Son") }
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .onChange(of: days) { _, _ in selectedIndex = nil }
        }
    }
}

private struct Sparkline: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        guard values.count > 1, rect.width > 0, rect.height > 0,
              let low = values.min(), let high = values.max(), high > low else { return Path() }
        let padding = rect.height * 0.12
        let points = values.enumerated().map { index, value in
            CGPoint(x: rect.minX + CGFloat(index) / CGFloat(values.count - 1) * rect.width,
                    y: rect.maxY - padding - CGFloat((value - low) / (high - low)) * (rect.height - padding * 2))
        }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1], next = points[index]
            path.addQuadCurve(to: CGPoint(x: (previous.x + next.x) / 2, y: (previous.y + next.y) / 2), control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

struct StockRow: View {
    let instrument: Instrument
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 12) {
            StockBadge(symbol: instrument.symbol)
            VStack(alignment: .leading, spacing: 5) {
                Text(instrument.symbol).font(.subheadline.weight(.semibold))
                Text(instrument.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if typeSize <= .large {
                PriceChart(instrument: instrument, compact: true).frame(width: 46).accessibilityHidden(true)
            }
            VStack(alignment: .trailing, spacing: 6) {
                Text(Money.formatted(instrument.price)).font(.subheadline.weight(.medium)).monospacedDigit()
                ChangeLabel(percent: instrument.changePercent)
            }.fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 5) { Text(title).foregroundStyle(.secondary); Text(value).monospacedDigit() }
                .font(.subheadline).padding(.vertical, 5)
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 14)
                Text(value).multilineTextAlignment(.trailing).monospacedDigit()
            }.font(.subheadline).padding(.vertical, 5)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ActionButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(RoundedRectangle(cornerRadius: 17))
            .foregroundStyle(prominent ? Palette.onAccent : Palette.accent)
            .background(prominent ? Palette.accent : Palette.raised, in: RoundedRectangle(cornerRadius: 17))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    let icon: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.title).foregroundStyle(Palette.accent)
                .frame(width: 62, height: 62).background(Palette.raised, in: RoundedRectangle(cornerRadius: 20))
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(.vertical, 34).padding(.horizontal, 20).frame(maxWidth: .infinity)
    }
}
