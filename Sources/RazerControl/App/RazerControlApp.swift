import SwiftUI

@main
struct RazerControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
                .background(Color.razerBg)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
    }
}
