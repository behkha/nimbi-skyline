import AppKit
import NimbiKit
import SkylineCore
import SwiftUI

/// Who draws at the notch (DESIGN.md 18.2, phase 1). Skyline never claims it: Relay owns it by
/// default, and Skyline has no island page to show there until phase 2. It only listens, so
/// the settings line stays true when the owner changes.
@MainActor
final class NotchWatch: ObservableObject {
    @Published private(set) var owner: String?
    private var observation: SurfaceClaim.Observation?

    init() {
        owner = SurfaceClaim.owner(of: .notch)
        observation = SurfaceClaim.observe { [weak self] claim in
            guard claim.surface == .notch else { return }
            self?.owner = SurfaceClaim.owner(of: .notch)
        }
    }

    func reread() { owner = SurfaceClaim.owner(of: .notch) }

    var ownedBySkyline: Bool { owner == Bundle.main.bundleIdentifier }

    /// "Notch is used by Relay", in words people know.
    var line: String {
        guard let owner else { return "Notch is free. Skyline stays in the menu bar." }
        if ownedBySkyline { return "Notch is set to Skyline, which has nothing to show there yet." }
        return "Notch is used by \(Self.appName(owner))"
    }

    static func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

/// `,`: the settings menu (DESIGN.md 8): header, grouped rows in a well, then plain rows.
struct SettingsView: View {
    @ObservedObject var location: LocationService
    @ObservedObject var notch: NotchWatch
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
                if notch.ownedBySkyline {
                    Button("Let it go") {
                        SurfaceClaim.setOwner(nil, of: .notch)
                        notch.reread()
                    }
                    .buttonStyle(PillButtonStyle())
                } else if notch.owner != nil {
                    Text("Skyline stays in the menu bar.")
                        .font(look.font(10.5))
                        .foregroundStyle(Nimbi.Text.dim)
                        .padding(.leading, 26)
                }
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
