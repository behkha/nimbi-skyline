import AppKit
import NimbiKit
import SkylineCore
import SwiftUI

/// `,`: the settings menu (DESIGN.md 8): header, grouped rows in a well, then plain rows.
struct SettingsView: View {
    @ObservedObject var location: LocationService
    @ObservedObject var model: SkyModel
    @ObservedObject var panel: PanelState
    @ObservedObject var notch: NotchOwnership
    var actions: PanelActions
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NimbiCloud(size: 22, mood: .relaxed, followsCursor: false, lively: false)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Skyline").font(look.font(13.5, .semibold)).foregroundStyle(Nimbi.Text.primary)
                    Text("Version \(Bundle.main.shortVersion)").font(look.font(10.5)).foregroundStyle(Nimbi.Text.dim)
                }
                Spacer()
                Button(action: actions.back) { KeyHint(key: "esc") }
                    .buttonStyle(.plain)
                    .help("Back · esc")
                    .accessibilityLabel("Back")
            }

            VStack(spacing: 0) {
                SettingsRow(icon: "location", title: "Place", value: placeValue, chevron: true, action: actions.choosePlace)
                divider
                SettingsRow(icon: "circle.lefthalf.filled", title: "Theme", value: look.theme.rawValue) {
                    LookSettings.setTheme(look.theme == .dark ? .black : .dark)
                }
                divider
                SettingsRow(icon: "textformat.size", title: "Text size", value: "\(Int((look.textScale * 100).rounded()))%") {
                    let scales = LookSettings.textScales
                    let i = scales.firstIndex(of: look.textScale) ?? 1
                    LookSettings.setTextScale(scales[(i + 1) % scales.count])
                }
                divider
                SettingsRow(icon: "square.grid.3x2", title: "Details", value: panel.conditionsStyle == .strip ? "What matters" : "Everything") {
                    panel.conditionsStyle = panel.conditionsStyle.other
                }
                divider
                SettingsRow(icon: "aqi.medium", title: "Air index", value: model.airScale.title) {
                    model.airScale = model.airScale == .european ? .us : .european
                }
            }
            .background(RoundedRectangle(cornerRadius: Nimbi.Radius.group, style: .continuous).fill(Nimbi.Surface.well))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .foregroundStyle(Nimbi.Text.dim)
                        .frame(width: 18)
                    Text(notch.line)
                        .foregroundStyle(Nimbi.Text.strong)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(look.font(12))
                HStack(spacing: 8) {
                    Text(notch.ownedByMe ? "Hover it for the next 12 hours." : "Skyline stays in the menu bar.")
                        .font(look.font(10.5))
                        .foregroundStyle(Nimbi.Text.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if notch.ownedByMe {
                        Button(notch.giveBackTitle) { notch.giveBack() }
                            .buttonStyle(PillButtonStyle())
                            .focusable(false)
                    } else {
                        Button("Use for Skyline") { notch.take() }
                            .buttonStyle(PillButtonStyle())
                            .focusable(false)
                    }
                }
                .padding(.leading, 26)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Nimbi.Radius.group, style: .continuous).fill(Nimbi.Surface.well))

            VStack(spacing: 0) {
                PlainRow(title: "About Skyline", action: actions.about)
                PlainRow(title: "Quit Skyline", key: "⌘Q") { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(width: 284 * look.textScale)
        .onAppear { notch.reread() }
    }

    private var divider: some View {
        Rectangle().fill(Nimbi.Line.row).frame(height: 0.5).padding(.leading, 36)
    }

    private var placeValue: String {
        switch location.mode {
        case .automatic: return location.place.map { "\($0.name) · here" } ?? "Follow my Mac"
        case .manual: return location.place?.name ?? "Pick a city"
        }
    }
}

private struct SettingsRow: View {
    var icon: String
    var title: String
    var value: String
    var chevron = false
    var action: () -> Void
    @ObservedObject private var look = NimbiAppearance.shared
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(look.font(12, .medium))
                    .foregroundStyle(Nimbi.Text.dim)
                    .frame(width: 18)
                Text(title)
                    .font(look.font(12.5))
                    .foregroundStyle(Nimbi.Text.message)
                Spacer(minLength: 6)
                Text(value)
                    .font(look.font(12))
                    .foregroundStyle(Nimbi.Text.dim)
                    .lineLimit(1)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(look.font(10, .semibold))
                        .foregroundStyle(Nimbi.Text.faint)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 30 * look.textScale)
            .background(RoundedRectangle(cornerRadius: Nimbi.Radius.menuRow, style: .continuous)
                .fill(hover ? Color.white.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct PlainRow: View {
    var title: String
    var key: String?
    var action: () -> Void
    @ObservedObject private var look = NimbiAppearance.shared
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(look.font(12.5))
                    .foregroundStyle(Nimbi.Text.message)
                Spacer()
                if let key { KeyHint(key: key) }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28 * look.textScale)
            .background(RoundedRectangle(cornerRadius: Nimbi.Radius.menuRow, style: .continuous)
                .fill(hover ? Color.white.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
