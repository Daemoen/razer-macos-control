import SwiftUI

@main
struct RazerControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var deviceManager = DeviceManager()
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var showSetupWizard = false

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(deviceManager)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
                .background(Color.razerBg)
                .onAppear {
                    deviceManager.startScanning()
                    if !hasCompletedSetup {
                        showSetupWizard = true
                    }
                }
                .sheet(isPresented: $showSetupWizard, onDismiss: {
                    hasCompletedSetup = true
                }) {
                    SetupWizardView(isPresented: $showSetupWizard)
                        .environmentObject(deviceManager)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
    }
}
