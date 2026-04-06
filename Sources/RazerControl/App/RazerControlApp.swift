import SwiftUI

@main
struct RazerControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var deviceManager = DeviceManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(deviceManager)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
                .background(Color.razerBg)
                .onAppear {
                    deviceManager.startScanning()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
    }
}
