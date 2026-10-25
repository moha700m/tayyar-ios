import SwiftUI

@main
struct TayyarApp: App {
    @State private var engine: SensorEngine = {
        let e = SensorEngine()
        #if DEBUG
        // Simulator-only screenshot fixture: the simulator has no magnetometer.
        if let v = UserDefaults.standard.string(forKey: "demoScore"), let d = Double(v) {
            e.available = true; e.baselineMagnitude = 45; e.humMeasurable = true
            e.humScore = d; e.magScore = d * 0.7; e.magDeviation = d * 40; e.humRatio = 1 + d * 3
            e.humLikely = d > 0.6; e.metalLikely = d > 0.4
        }
        #endif
        return e
    }()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
                .dynamicTypeSize(.xLarge ... .accessibility3)
        }
    }
}

enum Theme {
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.10)
    static let bg = Color(red: 0.07, green: 0.08, blue: 0.11)
    static let card = Color(red: 0.12, green: 0.13, blue: 0.17)
    static func level(_ s: Double) -> Color {
        s < 0.33 ? .green : (s < 0.66 ? amber : .red)
    }
}

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    var body: some View {
        if onboarded {
            TabView {
                ScanView().tabItem { Label("الفحص", systemImage: "bolt.horizontal.circle") }
                TestModeView().tabItem { Label("وضع التجربة", systemImage: "waveform.path.ecg") }
                SettingsView().tabItem { Label("الإعدادات", systemImage: "slider.horizontal.3") }
            }
        } else {
            OnboardingView { onboarded = true }
        }
    }
}
