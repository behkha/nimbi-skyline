import CoreLocation
import NimbiKit
import SkylineCore
import SwiftUI

/// L: follow the Mac, or pick a city. Searching is debounced, since every keystroke would
/// otherwise be a geocoder request.
struct PlacePicker: View {
    @ObservedObject var location: LocationService
    @ObservedObject var search: PlaceSearch
    var actions: PanelActions
    @ObservedObject private var look = NimbiAppearance.shared
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Place")
                    .font(look.font(13.5, .semibold))
                    .foregroundStyle(Nimbi.Text.primary)
                Spacer()
                Button(action: actions.back) { KeyHint(key: "esc") }
                    .buttonStyle(.plain)
                    .help("Back · esc")
                    .accessibilityLabel("Back")
            }
            HStack(spacing: 6) {
                modeChip("Follow my Mac", mode: .automatic)
                modeChip("Pick a city", mode: .manual)
            }
            if location.mode == .automatic, location.status == .needsCity {
                Text("Location is off for Skyline. Turn it on in System Settings → Privacy & Security → Location Services, or pick a city.")
                    .font(look.font(11.5))
                    .foregroundStyle(Nimbi.Text.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            field
            results
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(width: 318 * look.textScale)
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
    }

    private func modeChip(_ title: String, mode: LocationService.Mode) -> some View {
        let on = location.mode == mode
        return Button {
            if mode == .automatic { location.setMode(.automatic) } else { fieldFocused = true }
        } label: {
            Text(title)
                .font(look.font(11.5, .medium))
                .foregroundStyle(on ? Color.black : Nimbi.Text.strong)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Nimbi.Text.dim)
            TextField("Search for a city", text: $search.query)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onSubmit { if let place = search.selected { actions.choose(place) } }
        }
        .font(look.font(12.5))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().stroke(Color.white.opacity(fieldFocused ? 0.2 : 0), lineWidth: 1))
    }

    @ViewBuilder private var results: some View {
        switch search.state {
        case .idle:
            if let current = location.place, location.mode == .manual {
                note("Now showing \(current.name). Type to pick another city.")
            }
        case .searching:
            note("Looking…")
        case .failed:
            note("Can't search right now. Check the connection and try again.")
        case .done where search.results.isEmpty:
            note("No city by that name.")
        case .done:
            VStack(spacing: 2) {
                ForEach(Array(search.results.enumerated()), id: \.offset) { index, place in
                    Button { actions.choose(place) } label: {
                        HStack(spacing: 8) {
                            Text(place.name)
                                .font(look.font(13, .medium))
                                .foregroundStyle(Nimbi.Text.primary)
                            Spacer(minLength: 4)
                            Text(detail(place))
                                .font(look.font(10.5))
                                .foregroundStyle(Nimbi.Text.dim)
                                .lineLimit(1)
                            if index == search.selection { KeyHint(key: "↩") }
                        }
                        .padding(.horizontal, 9)
                        .frame(minHeight: 30 * look.textScale)
                        .background(RoundedRectangle(cornerRadius: Nimbi.Radius.row, style: .continuous)
                            .fill(index == search.selection ? Color.white.opacity(0.08) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(look.font(11.5))
            .foregroundStyle(Nimbi.Text.dim)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Time zone and rough position, enough to tell two Springfields apart.
    private func detail(_ place: Place) -> String {
        let c = place.coordinate
        let lat = String(format: "%.1f°%@", abs(c.latitude), c.latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.1f°%@", abs(c.longitude), c.longitude >= 0 ? "E" : "W")
        let zone = place.timeZoneID.map { $0.replacingOccurrences(of: "_", with: " ") }
        return [zone, "\(lat) \(lon)"].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The picker's search: debounced, one request at a time, keyboard selection.
@MainActor
final class PlaceSearch: ObservableObject {
    enum State { case idle, searching, done, failed }

    @Published var query = "" { didSet { if query != oldValue { schedule() } } }
    @Published private(set) var results: [Place] = []
    @Published private(set) var state = State.idle
    @Published var selection = 0

    private let location: LocationService
    private var task: Task<Void, Never>?

    init(location: LocationService) { self.location = location }

    var selected: Place? { results.indices.contains(selection) ? results[selection] : nil }

    func move(_ step: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(0, selection + step), results.count - 1)
    }

    func reset() {
        task?.cancel()
        query = ""
        results = []
        state = .idle
        selection = 0
    }

    private func schedule() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { results = []; state = .idle; return }
        state = .searching
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let found = try await self.location.search(text)
                guard !Task.isCancelled else { return }
                self.results = Array(found.prefix(6))
                self.selection = 0
                self.state = .done
            } catch {
                guard !Task.isCancelled else { return }
                // CLGeocoder reports "nothing found" as an error too.
                self.results = []
                self.state = (error as? CLError)?.code == .geocodeFoundNoResult ? .done : .failed
            }
        }
    }
}
