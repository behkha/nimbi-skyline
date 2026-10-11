import NimbiKit
import SkylineCore
import SwiftUI

/// Strip or grid, remembered (docs/design-choices.md, "Air, sun and UV").
enum ConditionsStyle: String {
    case strip, grid

    static let key = "ConditionsStyle"

    static var saved: ConditionsStyle {
        UserDefaults.standard.string(forKey: key).flatMap(ConditionsStyle.init(rawValue:)) ?? .strip
    }

    var other: ConditionsStyle { self == .strip ? .grid : .strip }
}

/// Everything around the temperature: the quiet strip (only what matters now) or the grid of
/// labelled tiles. D, or More/Less in the key row, switches between them.
struct ConditionsView: View {
    var conditions: Conditions
    var style: ConditionsStyle

    var body: some View {
        switch style {
        case .strip:
            FlowLayout(spacing: 5) {
                ForEach(conditions.chips) { ChipView(chip: $0) }
            }
        case .grid:
            // Rows of three, each tile as tall as the tallest in its row.
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(Array(stride(from: 0, to: conditions.tiles.count, by: 3)), id: \.self) { start in
                    GridRow {
                        ForEach(conditions.tiles[start..<min(start + 3, conditions.tiles.count)]) { TileView(tile: $0) }
                    }
                }
            }
        }
    }
}

/// The colors of the air bands, good to worst: state colors, then the heat ramp.
private func bandColor(_ band: Int) -> Color {
    [Nimbi.State.done, Color(hex: "#C8D64A"), Nimbi.Heat.yellow, Nimbi.Heat.orange, Nimbi.Heat.red, Color(hex: "#B0306A")][min(5, max(0, band))]
}

private struct ChipView: View {
    var chip: Conditions.Chip
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let band = chip.band {
                Circle().fill(bandColor(band)).frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 0.5 }
            }
            Text(chip.text)
                .font(look.font(11.5))
                .foregroundStyle(chip.tone == .warn ? Color(hex: "#FFD27A") : Nimbi.Text.strong)
            if let detail = chip.detail {
                Text(detail)
                    .font(look.font(10.5))
                    .foregroundStyle(Nimbi.Text.dim)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 8).padding(.vertical, 3.5)
        .background(Capsule().fill(chip.tone == .warn ? Nimbi.State.waiting.opacity(0.13) : Color.white.opacity(0.07)))
        .help(chip.spoken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.spoken)
    }
}

private struct TileView: View {
    var tile: Conditions.Tile
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tile.label.uppercased())
                .font(look.font(9.5, .semibold))
                .tracking(0.6)
                .foregroundStyle(Nimbi.Text.faint)
            Text(tile.value)
                .font(look.font(15, .semibold))
                .foregroundStyle(tile.tone == .warn ? Color(hex: "#FFD27A") : Nimbi.Text.primary)
                .monospacedDigit()
            Text(tile.meaning)
                .font(look.font(10.5))
                .foregroundStyle(Nimbi.Text.dim)
                .lineLimit(1)
                .truncationMode(.tail)
            if let meter = tile.meter {
                Meter(value: meter).padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8).padding(.top, 7).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: Nimbi.Radius.group, style: .continuous).fill(Nimbi.Surface.well))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.label): \(tile.value), \(tile.meaning)")
    }
}

/// Green to red with a marker: the air and UV scales.
private struct Meter: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Nimbi.State.done, Nimbi.Heat.yellow, Nimbi.Heat.orange, Nimbi.Heat.red],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(height: 3)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Nimbi.Surface.panel, lineWidth: 1.5))
                    .frame(width: 7, height: 7)
                    .offset(x: max(0, min(geo.size.width - 7, geo.size.width * value - 3.5)))
            }
            .frame(height: 7)
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}
