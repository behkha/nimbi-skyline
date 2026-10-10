import AppKit
import NimbiKit
import SwiftUI

/// "Skyline by nimbi" (DESIGN.md 1, 16): the cloud, the name, the version and MET's credit.
@MainActor
final class AboutWindow {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 320),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(Nimbi.Surface.window)
            w.contentView = NSHostingView(rootView: AboutView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            NimbiCloud(size: 56, mood: .relaxed)
                .frame(width: 56, height: 56)
                .padding(.top, 18)
            VStack(spacing: 3) {
                (Text("Skyline").foregroundColor(Nimbi.Text.primary)
                 + Text(" by nimbi").foregroundColor(Nimbi.Text.dim))
                    .font(.system(size: 17, weight: .semibold))
                Text("Version \(Bundle.main.shortVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(Nimbi.Text.faint)
            }
            Text("A little cloud that keeps an eye on the sky.")
                .font(.system(size: 12.5))
                .foregroundStyle(Nimbi.Text.message)
                .multilineTextAlignment(.center)
            VStack(spacing: 4) {
                Link("Weather data © MET Norway", destination: URL(string: "https://www.met.no/en")!)
                    .focusable(false)
                Link("CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    .focusable(false)
            }
            .font(.system(size: 11))
            .foregroundStyle(Nimbi.Text.dim)
            Text("Made by behkha")
                .font(.system(size: 10.5))
                .foregroundStyle(Nimbi.Text.faint)
                .padding(.bottom, 18)
        }
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
    }
}
